import 'package:flutter/widgets.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

/// User-facing copy for the editor.
///
/// English is the only implementation today; adding a locale means adding an
/// [EditorStrings] subclass and registering it in `editor_locale.dart`.
abstract class EditorStrings {
  const EditorStrings();

  String get appTitle;
  String get open;
  String get save;
  String get settings;
  String get pathHint;
  String get unsavedChanges;
  String get enterPathFirst;
  String openedPath(String path);
  String openFailed(Object error);
  String savedPath(String path);
  String saveFailed(Object error);
  String get keepOneNode;

  String get previewEmpty;
  String get selectANode;
  String get outline;
  String get real;
  String get resetPreview;
  String get editMode;
  String get interactMode;
  String get collapseInspector;
  String get expandInspector;
  String get useLightTheme;
  String get useDarkTheme;

  String get addNode;
  String get duplicateNode;
  String get deleteNode;
  String get activePredicates;

  String get identity;
  String get component;
  String get interactive;
  String get motion;
  String get id;
  String get rectNormalized;
  String get rectPixels;
  String get x;
  String get y;
  String get width;
  String get height;
  String get transform;
  String get rotateZ;
  String get rotateX;
  String get rotateY;
  String get perspective;
  String get scaleX;
  String get scaleY;
  String get moveX;
  String get moveY;
  String get pivotX;
  String get pivotY;
  String get layout;
  String get z;
  String get renderOrder;
  String get focusOrder;
  String get visibility;
  String get properties;
  String get none;
  String get removeProperty;
  String get addProperty;

  String get document;
  String get canvas;
  String get canvasFit;
  String get referenceWidth;
  String get referenceHeight;
  String get useSafeArea;
  String get background;
  String get backgroundKind;
  String get backgroundAsset;
  String get importBackground;
  String get backdrop;
  String get chooseFile;
  String get goUp;
  String get directoryHint;
  String get pathNotFound;
  String get backgroundColor;
  String get hexColor;
  String get apply;
  String get scrimOpacity;
  String get blurSigma;
  String get noVideoRenderer;
  String backgroundImported(String asset);
  String backgroundImportFailed(Object error);

  String get always;
  String get rule;
  String get nestedCondition;
  String get clear;
  String get match;
  String get allOf;
  String get anyOf;
  String get isOperator;
  String get isNotOperator;
  String get addClause;
  String get removeClause;
  String get presets;
  String get asleep;
  String get awake;
  String get authenticating;
  String get errorState;
  String get userSelected;
  String get advanced;
  String predicateLabel(ScenePredicate predicate);

  String get appearance;
  String get language;
  String get editorTheme;
  String get editing;
  String get confirmUnsavedChanges;
  String get gridSnap;
  String get previewAspectRatio;
  String get files;
  String get defaultScenePath;
  String get resetToDefaults;
  String get close;

  String get unsavedDialogTitle;
  String get unsavedDialogBody;
  String get discard;
  String get cancel;
}

/// Makes the active [EditorStrings] available to the widget tree.
class EditorStringsScope extends InheritedWidget {
  const EditorStringsScope({
    required this.strings,
    required super.child,
    super.key,
  });

  final EditorStrings strings;

  static EditorStrings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EditorStringsScope>();
    assert(scope != null, 'No EditorStringsScope found in the widget tree.');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(EditorStringsScope oldWidget) =>
      strings != oldWidget.strings;
}
