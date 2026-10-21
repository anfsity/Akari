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

  @override
  Widget build(BuildContext context) => StudioSelect<T>(
    value: value,
    values: values,
    onChanged: onChanged,
    label: label,
    formatValue: (value) => formatValue?.call(value) ?? value.name,
  );
}

/// Linked anchors follow their control without polling the render tree on
/// every frame while a menu is open, including inside a scrolled settings page.
class StudioSelect<T> extends StatefulWidget {
  const StudioSelect({
    required this.value,
    required this.values,
    required this.onChanged,
    required this.formatValue,
    this.label,
    this.placeholder,
    super.key,
  });

  final T? value;
  final Iterable<T> values;
  final ValueChanged<T> onChanged;
  final String Function(T) formatValue;
  final String? label;
  final Widget? placeholder;

  @override
  State<StudioSelect<T>> createState() => _StudioSelectState<T>();
}

class _StudioSelectState<T> extends State<StudioSelect<T>> {
  final _anchor = Object();

  @override
  Widget build(BuildContext context) => OverlayAnchor(
    anchor: _anchor,
    child: Select<T>(
      theme: const SelectTheme(adaptiveOverlay: false),
      overlayConfiguration: PopoverConfiguration(
        anchor: LinkedAnchor(_anchor),
        alignment: Alignment.topCenter,
        widthConstraint: PopoverConstraint.anchorFixedSize,
        offset: const Offset(0, 4),
      ),
      value: widget.value,
      placeholder: widget.placeholder,
      onChanged: (value) {
        if (value != null) widget.onChanged(value);
      },
      itemBuilder: (context, value) => Text(
        widget.label == null
            ? widget.formatValue(value)
            : '${widget.label}: ${widget.formatValue(value)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      popup: SelectPopup(
        items: SelectItemList(
          children: [
            for (final value in widget.values)
              SelectItemButton(
                value: value,
                child: Text(widget.formatValue(value)),
              ),
          ],
        ),
      ).call,
    ),
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
