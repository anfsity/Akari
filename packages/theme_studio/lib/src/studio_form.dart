import 'package:shadcn_flutter/shadcn_flutter.dart';

class StudioFormField extends StatelessWidget {
  const StudioFormField({
    required this.label,
    required this.controller,
    required this.inputKey,
    this.maxLines = 1,
    this.onSubmitted,
    this.onFocusLost,
    this.onChanged,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final Key inputKey;
  final int maxLines;
  final VoidCallback? onSubmitted;
  final VoidCallback? onFocusLost;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label).small().muted(),
        const Gap(6),
        Semantics(
          label: label,
          child: Focus(
            onFocusChange: (focused) {
              if (!focused) onFocusLost?.call();
            },
            child: TextField(
              key: inputKey,
              controller: controller,
              maxLines: maxLines,
              onChanged: onChanged,
              onSubmitted: onSubmitted == null
                  ? null
                  : (_) => onSubmitted?.call(),
            ),
          ),
        ),
      ],
    ),
  );
}

class StudioFieldRow extends StatelessWidget {
  const StudioFieldRow({required this.left, required this.right, super.key});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const Gap(12),
      Expanded(child: right),
    ],
  );
}

class StudioFormSection extends StatelessWidget {
  const StudioFormSection({
    required this.title,
    required this.children,
    this.compact = false,
    this.headerSpacing = 12,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool compact;
  final double headerSpacing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (compact) Text(title).small().semiBold() else Text(title).semiBold(),
      Gap(headerSpacing),
      ...children,
    ],
  );
}

class StudioEnumSelect<T extends Enum> extends StatelessWidget {
  const StudioEnumSelect({
    required this.value,
    required this.values,
    required this.onChanged,
    this.label,
    this.formatValue,
    super.key,
  });

  final T value;
  final Iterable<T> values;
  final ValueChanged<T> onChanged;
  final String? label;
  final String Function(T)? formatValue;

  String _getLabel(T value) => formatValue?.call(value) ?? value.name;

  @override
  Widget build(BuildContext context) => Select<T>(
    theme: const SelectTheme(adaptiveOverlay: false),
    value: value,
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
    itemBuilder: (context, value) =>
        Text(label == null ? _getLabel(value) : '$label: ${_getLabel(value)}'),
    popup: SelectPopup(
      items: SelectItemList(
        children: [
          for (final value in values)
            SelectItemButton(value: value, child: Text(_getLabel(value))),
        ],
      ),
    ).call,
  );
}

class StudioFormError extends StatelessWidget {
  const StudioFormError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.destructive),
  ).small();
}
