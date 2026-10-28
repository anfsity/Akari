import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_project/project.dart';

import 'studio_form.dart';

/// Owns only dialog drafts. The workspace owns synthesis and the new project;
/// dismissal is blocked while that command is publishing its result.
class StudioCreateTheme extends StatefulWidget {
  const StudioCreateTheme({
    required this.sourceLabel,
    required this.initialLocation,
    required this.existingNames,
    required this.onCreate,
    super.key,
  });

  final String sourceLabel;
  final String initialLocation;
  final Set<String> existingNames;
  final Future<void> Function(String packageName, String destination) onCreate;

  @override
  State<StudioCreateTheme> createState() => _StudioCreateThemeState();
}

class _StudioCreateThemeState extends State<StudioCreateTheme> {
  final _name = TextEditingController();
  late final _location = TextEditingController(text: widget.initialLocation);
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _chooseLocation() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose theme location',
        initialDirectory: _location.text,
      );
      if (mounted && selected != null) _location.text = selected;
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _name.text.trim();
    final packageName = 'theme_$name';
    try {
      getThemeBuilderName(packageName);
      if (widget.existingNames.contains(packageName)) {
        throw const FormatException(
          'A theme with this name is already open. Choose another name.',
        );
      }
      if (_location.text.trim().isEmpty) {
        throw const FormatException('Choose a location for the new theme.');
      }
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    String? failure;
    try {
      await widget.onCreate(
        packageName,
        Directory('${_location.text.trim()}/$name').absolute.path,
      );
    } on Object catch (error) {
      failure = switch (error) {
        FormatException(:final message) => message,
        FileSystemException(:final message) => message,
        _ => '$error',
      };
    }
    if (!mounted) return;
    setState(() {
      _creating = false;
      _error = failure;
    });
    if (failure == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_creating,
    child: AlertDialog(
      key: const ValueKey('studio-create-theme'),
      title: const Text('Create theme'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: math.max(160, MediaQuery.sizeOf(context).height - 220),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Start from ${widget.sourceLabel} with your current design and resources. The original theme stays intact.',
              ).small().muted(),
              const Gap(16),
              ExcludeFocus(
                excluding: _creating,
                child: IgnorePointer(
                  ignoring: _creating,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      StudioFormField(
                        label: 'Name',
                        inputKey: const ValueKey('create-theme-name'),
                        controller: _name,
                        onSubmitted: _create,
                      ),
                      const Text(
                        'Use lower-case letters, numbers, and underscores, starting with a letter.',
                      ).small().muted(),
                      const Gap(8),
                      StudioFormField(
                        label: 'Location',
                        inputKey: const ValueKey('create-theme-location'),
                        controller: _location,
                        onSubmitted: _create,
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: _creating ? null : _chooseLocation,
                child: const Text('Choose folder'),
              ),
              const Gap(12),
              ListenableBuilder(
                listenable: Listenable.merge([_name, _location]),
                builder: (context, _) => Text(
                  _name.text.trim().isEmpty
                      ? 'A new folder will be created here.'
                      : Directory(
                          '${_location.text.trim()}/${_name.text.trim()}',
                        ).absolute.path,
                ).small().muted(),
              ),
              if (_error case final error?) ...[
                const Gap(12),
                StudioFormError(error),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          key: const ValueKey('create-theme-confirm'),
          onPressed: _creating ? null : _create,
          child: Text(_creating ? 'Creating…' : 'Create theme'),
        ),
      ],
    ),
  );
}
