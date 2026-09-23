import 'dart:io';

import 'package:flutter/material.dart';

import 'editor_strings.dart';

/// A minimal, dependency-free file browser for the desktop editor.
///
/// Returns the chosen file, or null when the dialog is dismissed.
Future<File?> pickFile(BuildContext context, {Directory? initialDirectory}) {
  return showDialog<File>(
    context: context,
    builder: (context) => _FilePickerDialog(initialDirectory: initialDirectory),
  );
}

class _FilePickerDialog extends StatefulWidget {
  const _FilePickerDialog({this.initialDirectory});

  final Directory? initialDirectory;

  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  late Directory _directory;
  List<FileSystemEntity> _entries = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _directory = widget.initialDirectory ?? Directory.current;
    _load();
  }

  void _load() {
    try {
      final entries = _directory.listSync()
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
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _entries = const [];
        _error = '$error';
      });
    }
  }

  void _open(Directory directory) {
    _directory = directory;
    _load();
  }

  void _goUp() {
    final parent = _directory.parent;
    if (parent.path != _directory.path) {
      _open(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return AlertDialog(
      title: Text(strings.chooseFile),
      content: SizedBox(
        width: 560,
        height: 420,
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
                  child: Text(
                    _directory.path,
                    overflow: TextOverflow.ellipsis,
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
