import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:3000',
);

void main() => runApp(const SobatNiraApp());

class SobatNiraApp extends StatefulWidget {
  const SobatNiraApp({super.key, this.client});

  final http.Client? client;

  @override
  State<SobatNiraApp> createState() => _SobatNiraAppState();
}

class _SobatNiraAppState extends State<SobatNiraApp> {
  late Future<Map<String, dynamic>> _draft = _loadDraft();

  Future<Map<String, dynamic>> _loadDraft() async {
    final uri = Uri.parse('$apiBaseUrl/demo/draft');
    final response = await (widget.client?.get(uri) ?? http.get(uri)).timeout(
      const Duration(seconds: 5),
    );
    if (response.statusCode != 200) {
      throw StateError('API returned ${response.statusCode}');
    }
    final draft = jsonDecode(response.body) as Map<String, dynamic>;
    if (draft['synthetic'] != true) {
      throw const FormatException('Fixture sintetis diperlukan');
    }
    return draft;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SobatNira',
      home: Scaffold(
        appBar: AppBar(title: const Text('SobatNira')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _draft,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator(
                    semanticsLabel: 'Memuat draf sintetis',
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Draf belum tersedia. Periksa NestJS dan FastAPI.',
                      ),
                      TextButton(
                        onPressed: () {
                          final draft = _loadDraft();
                          setState(() {
                            _draft = draft;
                          });
                        },
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  );
                }
                final draft = snapshot.requireData;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Draf sintetis'),
                        Text('${draft['stage']} · ${draft['lotCode']}'),
                        Text(
                          '${draft['supplier']} · ${draft['netWeightKg']} kg',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
