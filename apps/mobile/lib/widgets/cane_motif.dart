import 'package:flutter/material.dart';

/// The two stalks and leaves used in the Keuntungan card pattern.
class CaneMotif {
  static final stems = _buildStems();
  static final leaves = Path()
    ..moveTo(6, 7)
    ..quadraticBezierTo(-6, 7, -5, -1)
    ..quadraticBezierTo(3, -1, 6, 7)
    ..close()
    ..moveTo(7, 7)
    ..quadraticBezierTo(7, -5, 17, -4)
    ..quadraticBezierTo(17, 4, 7, 7)
    ..close();

  static final silhouette = Path()
    ..addPath(stems, Offset.zero)
    ..addPath(leaves, Offset.zero);

  static Path _buildStems() {
    final path = Path();
    for (var stalk = 0; stalk < 2; stalk++) {
      for (var joint = 0; joint < 3; joint++) {
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(stalk * 7.0, joint * 7.0, 5, 6),
            const Radius.circular(1.3),
          ),
        );
      }
    }
    return path;
  }
}
