import 'editor_strings.dart';

/// The outcome the editor reports in its status bar.
enum EditorStatusKind {
  idle,
  enterPathFirst,
  opened,
  openFailed,
  saved,
  saveFailed,
  keepOneNode,
}

class EditorStatus {
  const EditorStatus(this.kind, [this.detail]);

  static const idle = EditorStatus(EditorStatusKind.idle);

  final EditorStatusKind kind;

  /// The path or error the message refers to, when the kind needs one.
  final Object? detail;
}

String describeEditorStatus(EditorStrings strings, EditorStatus status) {
  return switch (status.kind) {
    EditorStatusKind.idle => '',
    EditorStatusKind.enterPathFirst => strings.enterPathFirst,
    EditorStatusKind.opened => strings.openedPath(status.detail! as String),
    EditorStatusKind.openFailed => strings.openFailed(status.detail!),
    EditorStatusKind.saved => strings.savedPath(status.detail! as String),
    EditorStatusKind.saveFailed => strings.saveFailed(status.detail!),
    EditorStatusKind.keepOneNode => strings.keepOneNode,
  };
}
