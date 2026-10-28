import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Keeps preview updates separate from one final edit. shadcn can omit its
/// onChangeEnd after a controlled value catches up, so pointer release owns
/// the commit as well; keyboard and track taps still use onChangeEnd.
class StudioPreviewSlider extends StatefulWidget {
  const StudioPreviewSlider({
    required this.value,
    required this.maximum,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
    this.minimum = 0,
    super.key,
  });
  final double value;
  final double minimum;
  final double maximum;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;
  final VoidCallback onCancel;
  @override
  State<StudioPreviewSlider> createState() => _StudioPreviewSliderState();
}

class _StudioPreviewSliderState extends State<StudioPreviewSlider> {
  double? _draft;
  void _commit(double value) {
    _draft = null;
    widget.onCommit(value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerUp: (_) {
      if (_draft case final value?) _commit(value);
    },
    onPointerCancel: (_) {
      _draft = null;
      widget.onCancel();
    },
    child: Slider(
      value: SliderValue.single(
        widget.value.clamp(widget.minimum, widget.maximum),
      ),
      min: widget.minimum,
      max: widget.maximum,
      onChanged: (value) {
        _draft = value.value;
        widget.onPreview(value.value);
      },
      onChangeEnd: (value) => _commit(value.value),
    ),
  );
}

class StudioSliderField extends StatefulWidget {
  const StudioSliderField({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.maximum,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
    this.minimum = 0,
    this.decimals = 1,
    super.key,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int decimals;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;
  final VoidCallback onCancel;

  @override
  State<StudioSliderField> createState() => _StudioSliderFieldState();
}

class _StudioSliderFieldState extends State<StudioSliderField> {
  late final _controller = TextEditingController(
    text: widget.value.toStringAsFixed(widget.decimals),
  );
  final _focus = FocusNode();

  @override
  void didUpdateWidget(StudioSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus) {
      final text = widget.value.toStringAsFixed(widget.decimals);
      if (_controller.text != text) _controller.text = text;
    }
  }

  void _commitText() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _controller.text = widget.value.toStringAsFixed(widget.decimals);
      return;
    }
    final clamped = parsed.clamp(widget.minimum, widget.maximum);
    _controller.text = clamped.toStringAsFixed(widget.decimals);
    if ((clamped - widget.value).abs() > 1e-6) {
      widget.onCommit(clamped);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [
      Row(
        children: [
          Expanded(child: Text(widget.label).xSmall().muted()),
          const Gap(8),
          SizedBox(
            width: 58,
            child: Semantics(
              label: '${widget.label} value',
              child: Focus(
                focusNode: _focus,
                onFocusChange: (focused) {
                  if (!focused) _commitText();
                },
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.right,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  onSubmitted: (_) => _commitText(),
                ),
              ),
            ),
          ),
        ],
      ),
      StudioPreviewSlider(
        key: widget.sliderKey,
        value: widget.value,
        minimum: widget.minimum,
        maximum: widget.maximum,
        onPreview: widget.onPreview,
        onCommit: widget.onCommit,
        onCancel: widget.onCancel,
      ),
    ],
  );
}

class StudioFormField extends StatelessWidget {
  const StudioFormField({
    required this.label,
    required this.controller,
    required this.inputKey,
    this.prefix,
    this.maxLines = 1,
    this.onSubmitted,
    this.onFocusLost,
    this.onChanged,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final Key inputKey;
  final String? prefix;
  final int maxLines;
  final VoidCallback? onSubmitted;
  final VoidCallback? onFocusLost;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final input = Semantics(
      label: label,
      child: Focus(
        onFocusChange: (focused) {
          if (!focused) onFocusLost?.call();
        },
        child: TextField(
          key: inputKey,
          controller: controller,
          maxLines: maxLines,
          padding: maxLines == 1
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : const EdgeInsets.all(8),
          style: maxLines > 1
              ? Theme.of(context).typography.mono.copyWith(fontSize: 12)
              : TextStyle(
                  fontSize: 13,
                  fontFeatures: prefix != null
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
          features: [
            if (prefix case final badge?)
              InputFeature.leading(
                Tooltip(
                  tooltip: (_) => Text(label),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: badge.length <= 2 ? 14 : 32,
                    ),
                    child: Text(badge).xSmall().muted(),
                  ),
                ),
                skipFocusTraversal: true,
              ),
          ],
          onChanged: onChanged,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted?.call(),
        ),
      ),
    );
    if (prefix != null) return input;
    return StudioLabeledField(label: label, child: input);
  }
}

class StudioLabeledField extends StatelessWidget {
  const StudioLabeledField({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [Text(label).xSmall().muted(), child],
  );
}

class StudioSwitchRow extends StatelessWidget {
  const StudioSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 28),
    child: Row(
      children: [
        Expanded(child: Text(label).small()),
        const Gap(8),
        Switch(value: value, onChanged: onChanged),
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
    spacing: 8,
    children: [
      Expanded(child: left),
      Expanded(child: right),
    ],
  );
}

class StudioFormSection extends StatelessWidget {
  const StudioFormSection({
    required this.title,
    required this.children,
    this.trailing,
    this.headerSpacing = 10,
    this.spacing = 10,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final double headerSpacing;
  final double spacing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(title).small().semiBold()),
          if (trailing case final action?) ...[
            const Gap(8),
            action,
          ],
        ],
      ),
      Gap(headerSpacing),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: children,
      ),
    ],
  );
}

class StudioDisclosureSection extends StatefulWidget {
  const StudioDisclosureSection({
    required this.title,
    required this.child,
    this.triggerKey,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final Widget child;
  final Key? triggerKey;
  final bool initiallyExpanded;

  @override
  State<StudioDisclosureSection> createState() =>
      _StudioDisclosureSectionState();
}

class _StudioDisclosureSectionState extends State<StudioDisclosureSection> {
  late bool _expanded = widget.initiallyExpanded;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: widget.triggerKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: ColoredBox(
                color: _hovered
                    ? colors.muted.withValues(alpha: 0.5)
                    : Colors.transparent,
                child: SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text(widget.title).small().semiBold()),
                        Icon(
                          _expanded
                              ? LucideIcons.chevronDown
                              : LucideIcons.chevronRight,
                          size: 14,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: widget.child,
          ),
      ],
    );
  }
}

class StudioEnumSelect<T extends Enum> extends StatelessWidget {
  const StudioEnumSelect({
    required this.value,
    required this.values,
    required this.onChanged,
    this.label,
    this.formatValue,
    this.enabled = true,
    super.key,
  });

  final T value;
  final Iterable<T> values;
  final ValueChanged<T> onChanged;
  final String? label;
  final String Function(T)? formatValue;
  final bool enabled;

  @override
  Widget build(BuildContext context) => StudioSelect<T>(
    value: value,
    values: values,
    onChanged: onChanged,
    label: label,
    formatValue: (value) => formatValue?.call(value) ?? value.name,
    enabled: enabled,
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
    this.enabled = true,
    super.key,
  });

  final T? value;
  final Iterable<T> values;
  final ValueChanged<T> onChanged;
  final String Function(T) formatValue;
  final String? label;
  final Widget? placeholder;
  final bool enabled;

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
      enabled: widget.enabled,
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
      popup: SelectPopup<T>(
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
