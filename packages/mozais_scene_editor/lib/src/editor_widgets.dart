import 'package:flutter/material.dart';

/// A titled card that groups related editor controls.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled slider with the current value shown on the right.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(value.toStringAsFixed(2), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

/// A precise numeric field for dimensions that also have a slider control.
class LabeledNumberField extends StatelessWidget {
  const LabeledNumberField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.suffix = 'px',
    this.fractionDigits = 1,
    super.key,
  });

  final String fieldKey;
  final String label;
  final double value;
  final ValueChanged<double> onSubmitted;
  final String suffix;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$fieldKey:${value.toStringAsFixed(fractionDigits)}'),
      initialValue: value.toStringAsFixed(fractionDigits),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: fractionDigits > 0,
      ),
      textAlign: TextAlign.end,
      onFieldSubmitted: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null && parsed.isFinite) {
          onSubmitted(parsed);
        }
      },
    );
  }
}

/// A labelled dropdown over an enum's values.
class EnumDropdown<T extends Enum> extends StatelessWidget {
  const EnumDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            onChanged: (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
            items: [
              for (final option in values)
                DropdownMenuItem(value: option, child: Text(option.name)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled switch laid out as a row.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
