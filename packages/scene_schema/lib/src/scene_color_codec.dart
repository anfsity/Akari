/// Parses a `#RRGGBB` or `#AARRGGBB` scene color into a 32-bit ARGB value.
int decodeSceneColor(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('Color must use #RRGGBB or #AARRGGBB: $value');
  }
  final normalized = hex.length == 6 ? 'ff$hex' : hex;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    throw FormatException('Color must be hexadecimal: $value');
  }
  return parsed;
}

/// Formats a 32-bit ARGB value as a `#RRGGBB` or `#AARRGGBB` scene color.
String encodeSceneColor(int value) {
  final hex = value.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  if (hex.startsWith('ff')) {
    return '#${hex.substring(2)}';
  }
  return '#$hex';
}
