import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'editor_strings.dart';

/// A minimal, dependency-free file browser for the desktop editor.
///
/// [initialDirectory] defaults to the user's home directory. When
/// [extensions] is non-empty, only files with a matching extension (without
/// the leading dot, case-insensitive) are listed. Returns the chosen file, or
/// null when the dialog is dismissed.
Future<File?> pickFile(
  BuildContext context, {
  Directory? initialDirectory,
  Set<String> extensions = const {},
}) {
  return showDialog<File>(
    context: context,
    builder: (context) => _FilePickerDialog(
      initialDirectory: initialDirectory ?? homeDirectory(),
      extensions: extensions,
    ),
  );
}

/// The user's home directory, or null when it cannot be resolved.
Directory? homeDirectory() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  final directory = Directory(home);
  return directory.existsSync() ? directory : null;
}

class _FilePickerDialog extends StatefulWidget {
  const _FilePickerDialog({this.initialDirectory, this.extensions = const {}});

  final Directory? initialDirectory;
  final Set<String> extensions;

  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  late Directory _directory;
  late final TextEditingController _pathController;
  List<FileSystemEntity> _entries = const [];
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _directory = widget.initialDirectory ?? Directory.current;
    _pathController = TextEditingController(text: _directory.path);
    unawaited(_load());
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final directory = _directory;
    try {
      final entries = await directory.list().toList()
        ..sort((left, right) {
          final leftIsDirectory = left is Directory;
          final rightIsDirectory = right is Directory;
          if (leftIsDirectory != rightIsDirectory) {
            return leftIsDirectory ? -1 : 1;
          }
          return _name(left).toLowerCase().compareTo(
            _name(right).toLowerCase(),
          );
        });
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _entries = entries.where(_isVisible).toList();
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _entries = const [];
        _error = '$error';
      });
    }
  }

  bool _isVisible(FileSystemEntity entity) {
    if (entity is Directory) {
      return true;
    }
    if (widget.extensions.isEmpty) {
      return true;
    }
    final name = _name(entity);
    final dot = name.lastIndexOf('.');
    if (dot < 0) {
      return false;
    }
    return widget.extensions.contains(name.substring(dot + 1).toLowerCase());
  }

  void _open(Directory directory) {
    _directory = directory;
    _pathController.text = directory.path;
    setState(() {
      _entries = const [];
      _error = null;
    });
    unawaited(_load());
  }

  void _goUp() {
    final parent = _directory.parent;
    if (parent.path != _directory.path) {
      _open(parent);
    }
  }

  void _submitPath(String value) {
    final path = value.trim();
    if (path.isEmpty) {
      return;
    }
    final directory = Directory(path);
    if (directory.existsSync()) {
      _open(directory);
      return;
    }
    final file = File(path);
    if (file.existsSync()) {
      Navigator.of(context).pop(file);
      return;
    }
    setState(() => _error = EditorStringsScope.of(context).pathNotFound);
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return AlertDialog(
      title: Text(strings.chooseFile),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: strings.goUp,
                  onPressed: _goUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: strings.directoryHint,
                    ),
                    onSubmitted: _submitPath,
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : ListView(
                      children: [
                        for (final entry in _entries) _entryTile(entry),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
      ],
    );
  }

  Widget _entryTile(FileSystemEntity entry) {
    final name = _name(entry);
    if (entry is Directory) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.folder_outlined),
        title: Text(name),
        onTap: () => _open(entry),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(name),
      onTap: () => Navigator.of(context).pop(File(entry.path)),
    );
  }
}

String _name(FileSystemEntity entity) =>
    entity.path.split(Platform.pathSeparator).last;
