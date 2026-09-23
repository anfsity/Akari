import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'editor_strings.dart';

/// A curated palette offered by the color picker.
const editorColorPalette = <int>[
  0xff000000,
  0xff1e1e2e,
  0xff313244,
  0xff45475a,
  0xff585b70,
  0xff6c7086,
  0xff9399b2,
  0xffcdd6f4,
  0xffffffff,
  0xfff38ba8,
  0xffeba0ac,
  0xfffab387,
  0xfff9e2af,
  0xffa6e3a1,
  0xff94e2d5,
  0xff89dceb,
  0xff89b4fa,
  0xffcba6f7,
  0xffe64553,
  0xfffe640b,
  0xffdf8e1d,
  0xff40a02b,
  0xff179299,
  0xff04a5e5,
  0xff1e66f5,
  0xff8839ef,
];

/// Shows a palette and hex field, returning the chosen ARGB color or null.
Future<int?> pickEditorColor(BuildContext context, {required int initial}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final int initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int _value = widget.initial;
  late final TextEditingController _hexController = TextEditingController(
    text: encodeSceneColor(widget.initial),
  );

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _select(int value) {
    setState(() {
      _value = value;
      _hexController.text = encodeSceneColor(value);
    });
  }

  void _submitHex(String text) {
    try {
      _select(decodeSceneColor(text.trim()));
    } on FormatException {
      // Keep the previous color when the field is not a valid hex value.
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return AlertDialog(
      title: Text(strings.backgroundColor),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in editorColorPalette)
                  _ColorSwatch(
                    color: color,
                    selected: color == _value,
                    onTap: () => _select(color),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hexController,
              decoration: InputDecoration(
                labelText: strings.hexColor,
                isDense: true,
              ),
              onSubmitted: _submitHex,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(strings.apply),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color: ThemeData.estimateBrightnessForColor(Color(color)) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }
}
