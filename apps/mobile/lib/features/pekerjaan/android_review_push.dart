import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'review_api.dart';

class AndroidReviewPush extends ChangeNotifier {
  AndroidReviewPush(this.api, this.factory, this.openReview);

  static const _savedAccount = 'sobatnira.review_push.account';
  static const _savedInstallation = 'sobatnira.review_push.installation';
  static const _pendingRevoke = 'sobatnira.review_push.pending_revoke';
  static bool get supported =>
      const bool.fromEnvironment('SOBATNIRA_ANDROID_PUSH') &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  final ReviewApi api;
  final FactoryScope factory;
  final VoidCallback openReview;
  final _prefs = SharedPreferencesAsync();
  FirebaseMessaging? _provider;
  StreamSubscription<String>? _registrations;
  StreamSubscription<RemoteMessage>? _taps;
  Future<void>? _currentWrite;
  Completer<void>? _registration;
  String? _installation;
  bool _wanted = false;
  bool _closed = false;

  bool get available => factory.role == 'admin' && api.accountId != null;
  bool enabled = false;
  bool busy = false;
  String? error;

  late final Future<void> started = _start();

  Future<void> _start() async {
    try {
      await Firebase.initializeApp();
      if (_closed) return;
      final messaging = _provider = FirebaseMessaging.instance;
      _registrations = messaging.onRegistered.listen((id) {
        if (_wanted && !_closed) {
          _currentWrite = (_currentWrite ?? Future<void>.value()).then(
            (_) => _store(id),
          );
        }
      });
      if (available) {
        _taps = FirebaseMessaging.onMessageOpenedApp.listen(_open);
        _open(await messaging.getInitialMessage());
      }
      final account = await _prefs.getString(_savedAccount);
      _installation = await _prefs.getString(_savedInstallation);
      if (_closed || account == null) return;
      if (account != api.accountId ||
          await _prefs.getBool(_pendingRevoke) == true) {
        await _revoke();
      } else if (available) {
        final permission = await messaging.getNotificationSettings();
        if (permission.authorizationStatus == AuthorizationStatus.authorized) {
          await _requestRegistration(messaging);
        } else {
          await _revoke();
        }
      }
    } catch (_) {
      if (!_closed) {
        error = 'Notifikasi Android belum tersambung. Coba lagi.';
        notifyListeners();
      }
    }
  }

  Future<void> toggle() async {
    if (busy || !available) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await started;
      if (_closed) return;
      if (enabled) {
        await _revoke();
      } else {
        final messaging = _provider;
        if (messaging == null) {
          throw StateError('Firebase belum dikonfigurasi.');
        }
        final permission = await messaging.requestPermission(
          sound: true,
          alert: true,
        );
        if (permission.authorizationStatus != AuthorizationStatus.authorized) {
          error = 'Izinkan notifikasi SobatNira di pengaturan Android.';
        } else {
          await _requestRegistration(messaging);
        }
      }
    } catch (_) {
      error = 'Notifikasi Android belum tersambung. Coba lagi.';
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _requestRegistration(FirebaseMessaging messaging) async {
    if (_closed) return;
    _wanted = true;
    final registration = _registration = Completer<void>();
    try {
      await Future.wait([
        messaging.register(),
        registration.future,
      ]).timeout(const Duration(seconds: 15));
    } finally {
      if (_registration == registration) _registration = null;
    }
  }

  Future<void> _store(String installation) async {
    if (!_wanted || _closed) return;
    try {
      final previous = _installation;
      await api.registerReviewPush(installation, factory.factoryId);
      _installation = installation;
      if (previous != null && previous != installation) {
        await api.revokeReviewPush(previous);
      }
      await _prefs.setString(_savedAccount, api.accountId!);
      await _prefs.setString(_savedInstallation, installation);
      enabled = true;
      error = null;
      final registration = _registration;
      if (registration != null && !registration.isCompleted) {
        registration.complete();
      }
    } catch (cause, stack) {
      final registration = _registration;
      if (registration != null && !registration.isCompleted) {
        registration.completeError(cause, stack);
      }
    }
    if (!_closed) notifyListeners();
  }

  void _open(RemoteMessage? message) {
    if (!_closed && message?.data['screen'] == 'review') openReview();
  }

  Future<void> signOut() async {
    await started;
    if (_provider == null) return;
    try {
      await _revoke();
    } catch (_) {
      // Both the server revocation and Firebase unregistration are attempted.
    }
  }

  Future<void> _revoke() async {
    _wanted = false;
    await _currentWrite;
    if (_installation == null) return;
    await _prefs.setBool(_pendingRevoke, true);
    final pending = <Future<void>>[
      if (_installation case final id?) api.revokeReviewPush(id),
      if (_provider case final messaging?) messaging.unregister(),
    ];
    try {
      await Future.wait(pending).timeout(const Duration(seconds: 12));
      _installation = null;
      await _prefs.remove(_savedAccount);
      await _prefs.remove(_savedInstallation);
      await _prefs.remove(_pendingRevoke);
    } finally {
      enabled = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_registrations?.cancel());
    unawaited(_taps?.cancel());
    super.dispose();
  }
}
