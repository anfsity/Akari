int getIntegerInput(String label, String text) {
  final value = int.tryParse(text);
  if (value == null) throw FormatException('$label must be an integer.');
  return value;
}

double getFiniteNumberInput(String label, String text) {
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) {
    throw FormatException('$label must be a finite number.');
  }
  return value;
}
