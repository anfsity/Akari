import 'package:flutter/material.dart';

import 'editor_locale.dart';
import 'editor_settings.dart';
import 'editor_settings_controller.dart';
import 'editor_strings.dart';
import 'editor_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.controller, super.key});

  final EditorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settings),
        actions: [
          TextButton(
            onPressed: controller.resetToDefaults,
            child: Text(strings.resetToDefaults),
          ),
          IconButton(
            tooltip: strings.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final settings = controller.settings;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Group(
                      title: strings.appearance,
                      children: [
                        _ThemePicker(controller: controller),
                        const SizedBox(height: 12),
                        _LanguagePicker(controller: controller),
                      ],
                    ),
                    _Group(
                      title: strings.editing,
                      children: [
                        _SwitchRow(
                          label: strings.confirmUnsavedChanges,
                          value: settings.confirmUnsavedChanges,
                          onChanged: (value) => controller.update(
                            settings.copyWith(confirmUnsavedChanges: value),
                          ),
                        ),
                        _SwitchRow(
                          label: strings.gridSnap,
                          value: settings.gridSnap,
                          onChanged: (value) => controller.update(
                            settings.copyWith(gridSnap: value),
                          ),
                        ),
                        _AspectRatioPicker(controller: controller),
                      ],
                    ),
                    _Group(
                      title: strings.files,
                      children: [
                        _DefaultPathField(controller: controller),
                      ],
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _LivePreview(strings: strings),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.controller});

  final EditorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    final settings = controller.settings;
    return Row(
      children: [
        SizedBox(width: 160, child: Text(strings.editorTheme)),
        Expanded(
          child: DropdownButton<EditorThemeId>(
            isExpanded: true,
            value: settings.themeId,
            onChanged: (value) {
              if (value != null) {
                controller.update(settings.copyWith(themeId: value));
              }
            },
            items: [
              for (final theme in editorThemes.values)
                DropdownMenuItem(value: theme.id, child: Text(theme.name)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.controller});

  final EditorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    final settings = controller.settings;
    return Row(
      children: [
        SizedBox(width: 160, child: Text(strings.language)),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: settings.locale,
            onChanged: (value) {
              if (value != null) {
                controller.update(settings.copyWith(locale: value));
              }
            },
            items: [
              for (final locale in editorLocales)
                DropdownMenuItem(value: locale.code, child: Text(locale.name)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AspectRatioPicker extends StatelessWidget {
  const _AspectRatioPicker({required this.controller});

  final EditorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    final settings = controller.settings;
    return Row(
      children: [
        SizedBox(width: 160, child: Text(strings.previewAspectRatio)),
        Expanded(
          child: DropdownButton<double>(
            isExpanded: true,
            value: settings.previewAspectRatio,
            onChanged: (value) {
              if (value != null) {
                controller.update(settings.copyWith(previewAspectRatio: value));
              }
            },
            items: [
              for (final ratio in editorAspectRatios.entries)
                DropdownMenuItem(value: ratio.value, child: Text(ratio.key)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
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

class _DefaultPathField extends StatelessWidget {
  const _DefaultPathField({required this.controller});

  final EditorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return TextFormField(
      key: ValueKey(settings.defaultScenePath),
      initialValue: settings.defaultScenePath,
      decoration: InputDecoration(
        labelText: EditorStringsScope.of(context).defaultScenePath,
        hintText: EditorStringsScope.of(context).pathHint,
        isDense: true,
      ),
      onFieldSubmitted: (value) => controller.update(
        settings.copyWith(defaultScenePath: value.trim()),
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.strings});

  final EditorStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.settingsLivePreview,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final color in [
                  scheme.primary,
                  scheme.secondary,
                  scheme.tertiary,
                  scheme.surfaceContainerHighest,
                  scheme.outline,
                ])
                  Expanded(
                    child: Container(
                      height: 28,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {},
              child: Text(strings.save),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(isDense: true),
            ),
            const SizedBox(height: 8),
            Slider(value: 0.5, onChanged: (_) {}),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(label: Text(strings.visibility)),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(strings.rule),
                  selected: true,
                  onSelected: (_) {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
