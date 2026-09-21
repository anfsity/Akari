import 'editor_strings.dart';

/// The default, English copy for the editor.
class EnglishStrings extends EditorStrings {
  const EnglishStrings();

  @override
  String get appTitle => 'Mozais Scene Editor';
  @override
  String get open => 'Open';
  @override
  String get save => 'Save';
  @override
  String get settings => 'Settings';
  @override
  String get pathHint => 'path/to/scene.json';
  @override
  String get unsavedChanges => 'unsaved changes';
  @override
  String get enterPathFirst => 'Enter a scene path first.';
  @override
  String openedPath(String path) => 'Opened $path';
  @override
  String openFailed(Object error) => 'Open failed: $error';
  @override
  String savedPath(String path) => 'Saved $path';
  @override
  String saveFailed(Object error) => 'Save failed: $error';
  @override
  String get keepOneNode => 'A scene must keep at least one node.';

  @override
  String get previewEmpty => 'Open a scene to preview it.';
  @override
  String get selectANode => 'Select a node.';
  @override
  String get outline => 'Outline';
  @override
  String get real => 'Real';

  @override
  String get addNode => 'Add node';
  @override
  String get duplicateNode => 'Duplicate node';
  @override
  String get deleteNode => 'Delete node';
  @override
  String get activePredicates => 'Active predicates';

  @override
  String get identity => 'Identity';
  @override
  String get kind => 'kind';
  @override
  String get action => 'action';
  @override
  String get motion => 'motion';
  @override
  String get id => 'id';
  @override
  String get rectNormalized => 'Rect (normalized)';
  @override
  String get x => 'x';
  @override
  String get y => 'y';
  @override
  String get width => 'width';
  @override
  String get height => 'height';
  @override
  String get transform => 'Transform';
  @override
  String get rotateZ => 'rotate Z';
  @override
  String get rotateX => 'rotate X';
  @override
  String get rotateY => 'rotate Y';
  @override
  String get perspective => 'perspective';
  @override
  String get scaleX => 'scale X';
  @override
  String get scaleY => 'scale Y';
  @override
  String get moveX => 'move X';
  @override
  String get moveY => 'move Y';
  @override
  String get pivotX => 'pivot X';
  @override
  String get pivotY => 'pivot Y';
  @override
  String get layout => 'Layout';
  @override
  String get z => 'z';
  @override
  String get renderOrder => 'renderOrder';
  @override
  String get focusOrder => 'focusOrder';
  @override
  String get visibility => 'Visibility';
  @override
  String get properties => 'Properties';
  @override
  String get none => 'none';
  @override
  String get removeProperty => 'Remove property';
  @override
  String get addProperty => 'Add property';

  @override
  String get always => 'Always';
  @override
  String get rule => 'Rule';
  @override
  String get nestedCondition => 'Nested condition. Edit it in the JSON file.';
  @override
  String get clear => 'Clear';
  @override
  String get match => 'Match';
  @override
  String get allOf => 'all of';
  @override
  String get anyOf => 'any of';
  @override
  String get isOperator => 'is';
  @override
  String get isNotOperator => 'is not';
  @override
  String get addClause => 'Add clause';
  @override
  String get removeClause => 'Remove clause';

  @override
  String get appearance => 'Appearance';
  @override
  String get language => 'Language';
  @override
  String get editorTheme => 'Editor theme';
  @override
  String get editing => 'Editing';
  @override
  String get confirmUnsavedChanges => 'Confirm unsaved changes';
  @override
  String get gridSnap => 'Grid snap';
  @override
  String get previewAspectRatio => 'Preview aspect ratio';
  @override
  String get files => 'Files';
  @override
  String get defaultScenePath => 'Default scene path';
  @override
  String get settingsLivePreview => 'Live preview';
  @override
  String get resetToDefaults => 'Reset to defaults';
  @override
  String get close => 'Close';

  @override
  String get unsavedDialogTitle => 'Unsaved changes';
  @override
  String get unsavedDialogBody => 'Save changes before continuing?';
  @override
  String get discard => 'Discard';
  @override
  String get cancel => 'Cancel';
}
