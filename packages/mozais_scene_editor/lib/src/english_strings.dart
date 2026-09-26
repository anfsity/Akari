import 'package:mozais_scene_schema/mozais_scene_schema.dart';

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
  String get resetPreview => 'Reset real preview';
  @override
  String get editMode => 'Edit';
  @override
  String get interactMode => 'Interact';
  @override
  String get collapseInspector => 'Collapse inspector';
  @override
  String get expandInspector => 'Expand inspector';
  @override
  String get useLightTheme => 'Use light theme';
  @override
  String get useDarkTheme => 'Use dark theme';

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
  String get component => 'component';
  @override
  String get interactive => 'interactive';
  @override
  String get motion => 'motion';
  @override
  String get id => 'id';
  @override
  String get rectNormalized => 'Rect (normalized)';
  @override
  String get rectPixels => 'Exact values';
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
  String get document => 'Document';
  @override
  String get canvas => 'Canvas';
  @override
  String get canvasFit => 'fit';
  @override
  String get referenceWidth => 'Reference width';
  @override
  String get referenceHeight => 'Reference height';
  @override
  String get useSafeArea => 'Use safe area';
  @override
  String get background => 'Background';
  @override
  String get backgroundKind => 'kind';
  @override
  String get backgroundAsset => 'asset';
  @override
  String get importBackground => 'Import background';
  @override
  String get backdrop => 'Backdrop';
  @override
  String get chooseFile => 'Choose file';
  @override
  String get goUp => 'Up';
  @override
  String get directoryHint => 'Type a folder or file path';
  @override
  String get pathNotFound => 'No file or folder at that path.';
  @override
  String get backgroundColor => 'color';
  @override
  String get hexColor => 'Hex color';
  @override
  String get apply => 'Apply';
  @override
  String get scrimOpacity => 'scrim opacity';
  @override
  String get blurSigma => 'blur sigma';
  @override
  String get noVideoRenderer =>
      'No video renderer yet; this background renders solid.';
  @override
  String backgroundImported(String asset) => 'Imported $asset';
  @override
  String backgroundImportFailed(Object error) =>
      'Background import failed: $error';

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
  String get presets => 'Presets';
  @override
  String get asleep => 'asleep';
  @override
  String get awake => 'awake';
  @override
  String get authenticating => 'authenticating';
  @override
  String get errorState => 'error';
  @override
  String get userSelected => 'user selected';
  @override
  String get advanced => 'Advanced';

  @override
  String predicateLabel(ScenePredicate predicate) => switch (predicate) {
    ScenePredicate.isDormant => 'asleep',
    ScenePredicate.isServiceStarting => 'service starting',
    ScenePredicate.isServiceReady => 'service ready',
    ScenePredicate.isServiceUnavailable => 'service unavailable',
    ScenePredicate.isUserSelection => 'user selection',
    ScenePredicate.isAuthPrompting => 'prompting for credentials',
    ScenePredicate.isAuthSubmitting => 'submitting credentials',
    ScenePredicate.isSessionSelection => 'session selection',
    ScenePredicate.isHandingOff => 'handing off',
    ScenePredicate.isAuthError => 'authentication error',
    ScenePredicate.hasSelectedUser => 'user selected',
    ScenePredicate.isSessionLoading => 'loading sessions',
    ScenePredicate.isSessionReady => 'session ready',
    ScenePredicate.isSessionEmpty => 'no sessions',
    ScenePredicate.isSessionFailed => 'session failed',
    ScenePredicate.isPowerExecuting => 'power action running',
    ScenePredicate.hasPowerError => 'power action error',
  };

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
