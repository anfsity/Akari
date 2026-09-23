import 'package:flutter/material.dart';

import 'editor_locale.dart';
import 'editor_settings.dart';
import 'editor_settings_controller.dart';
import 'editor_strings.dart';
import 'editor_theme.dart';
import 'editor_widgets.dart';

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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: strings.appearance,
                children: [
                  _ThemePicker(controller: controller),
                  const SizedBox(height: 12),
                  _LanguagePicker(controller: controller),
                ],
              ),
              SectionCard(
                title: strings.editing,
                children: [
                  SwitchRow(
                    label: strings.confirmUnsavedChanges,
                    value: settings.confirmUnsavedChanges,
                    onChanged: (value) => controller.update(
                      settings.copyWith(confirmUnsavedChanges: value),
                    ),
                  ),
                  SwitchRow(
                    label: strings.gridSnap,
                    value: settings.gridSnap,
                    onChanged: (value) =>
                        controller.update(settings.copyWith(gridSnap: value)),
                  ),
                  _AspectRatioPicker(controller: controller),
                ],
              ),
              SectionCard(
                title: strings.files,
                children: [_DefaultPathField(controller: controller)],
              ),
            ],
          );
        },
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
          child: DropdownButtonHideUnderline(
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
                  DropdownMenuItem(
                    value: theme.id,
                    child: Row(
                      children: [
                        _ThemeSwatch(color: theme.palette.accent),
                        const SizedBox(width: 10),
                        Text(theme.name),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
      child: const SizedBox(width: 12, height: 12),
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
      onFieldSubmitted: (value) =>
          controller.update(settings.copyWith(defaultScenePath: value.trim())),
    );
  }
}
