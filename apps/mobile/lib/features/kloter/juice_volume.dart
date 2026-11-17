String _shift(String value, int places) {
  final parts = value.split('.');
  final digits = parts.join();
  final point = parts.first.length + places;
  final padded = point <= 0
      ? '${'0' * (1 - point)}$digits'
      : digits.padRight(point, '0');
  final split = point <= 0 ? 1 : point;
  final whole = padded
      .substring(0, split)
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String? litersToMilliliters(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.length > 64 || !RegExp(r'^(0|[1-9]\d*)(\.\d+)?$').hasMatch(text)) {
    return null;
  }
  final result = _shift(text, 3);
  return result == '0' || result.length > 64 ? null : result;
}

String millilitersToLiters(String value) => _shift(value, -3);

int compareJuiceVolumes(String left, String right) {
  final a = left.split('.');
  final b = right.split('.');
  final aFraction = a.length == 2 ? a.last : '';
  final bFraction = b.length == 2 ? b.last : '';
  final length = aFraction.length > bFraction.length
      ? aFraction.length
      : bFraction.length;
  return BigInt.parse(
    a.first + aFraction.padRight(length, '0'),
  ).compareTo(BigInt.parse(b.first + bFraction.padRight(length, '0')));
}
