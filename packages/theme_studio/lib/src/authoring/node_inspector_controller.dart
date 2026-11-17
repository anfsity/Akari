import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:scene/scene.dart';

import '../ui/studio_form_values.dart';

enum StudioLayoutUnit { pixels, percent }

const _layoutFields = {'X', 'Y', 'Width', 'Height'};

const _defaultMotionCurve = SceneCubicBezier(.2, 0, .2, 1);

/// Owns drafts independently of the inspector widget's mount lifecycle. The
/// editor commits them at document-command boundaries; the view only edits
/// fields and observes validation results.
class NodeInspectorController extends ChangeNotifier {
  NodeInspectorController(SceneNode node, this._canvas) {
    resetNode(node);
  }

  final _fields = <String, TextEditingController>{};
  bool _initialized = false;
  late SceneNode _node;
  SceneCanvas _canvas;
  StudioLayoutUnit _layoutUnit = StudioLayoutUnit.pixels;
  int _editingBreakpoint = -1;
  late SceneSizing _sizingDraft;
  SceneLayout? _layoutDraft;
  late SceneMotionPreset _motion;
  bool _hasCustomMotionCurve = false;
  String? _lastEditedField;
  String? _error;
  bool _hasDraft = false;
  bool _updatingFields = false;

  SceneNode get node => _node;
  int get editingBreakpoint => _editingBreakpoint;
  SceneBreakpoint? get editingBreakpointRule =>
      _editingBreakpoint < 0 ? null : _node.breakpoints[_editingBreakpoint];
  SceneSizing get sizing => _sizingDraft;
  SceneLayout? get layout => _layoutDraft;
  SceneMotionPreset get motion => _motion;
  bool get hasCustomMotionCurve => _hasCustomMotionCurve;
  String? get error => _error;
  bool get hasDraft => _hasDraft;
  StudioLayoutUnit get layoutUnit => _layoutUnit;
  TextEditingController getField(String label) => _fields[label]!;

  SceneCubicBezier? get motionCurvePreview {
    if (!_hasCustomMotionCurve) return null;
    try {
      return SceneCubicBezier(
        _getNumber('Bezier X1'),
        _getNumber('Bezier Y1'),
        _getNumber('Bezier X2'),
        _getNumber('Bezier Y2'),
      );
    } on FormatException {
      return _node.motionTiming.curve ?? _defaultMotionCurve;
    }
  }

  void _onFieldChanged(String label) {
    if (_updatingFields) return;
    _lastEditedField = label;
    if (label.startsWith('Bezier') && !_hasCustomMotionCurve) {
      _hasCustomMotionCurve = true;
      _markDraftChanged(forceNotify: true);
      return;
    }
    _markDraftChanged();
  }

  void _markDraftChanged({bool forceNotify = false}) {
    if (_updatingFields) return;
    final hadDraft = _hasDraft;
    _hasDraft = true;
    if (!hadDraft || forceNotify) notifyListeners();
  }

  void selectEditingBreakpoint(int index) {
    if (index < -1 || index >= _node.breakpoints.length) {
      throw RangeError.range(index, -1, _node.breakpoints.length - 1, 'index');
    }
    if (index == _editingBreakpoint) return;
    _editingBreakpoint = index;
    _updatingFields = true;
    try {
      _syncActiveRuleDraft(_node);
      if (_lastEditedField != null && _isLayoutRuleField(_lastEditedField!)) {
        _lastEditedField = null;
      }
      _hasDraft = _isModifiedFromCommitted();
      if (!_hasDraft) _error = null;
    } finally {
      _updatingFields = false;
    }
    notifyListeners();
  }

  void updateLayoutOptions({
    SceneLayoutDirection? direction,
    SceneMainAlignment? mainAlignment,
    SceneCrossAlignment? crossAlignment,
    SceneSizeMode? widthMode,
    SceneSizeMode? heightMode,
    bool? clip,
    bool? wrap,
  }) {
    _updatingFields = true;
    try {
      if (widthMode != null) getField('Fixed width').text = '';
      if (heightMode != null) getField('Fixed height').text = '';
      _sizingDraft = SceneSizing(
        width: widthMode != null ? null : _sizingDraft.width,
        height: heightMode != null ? null : _sizingDraft.height,
        widthMode: widthMode ?? _sizingDraft.widthMode,
        heightMode: heightMode ?? _sizingDraft.heightMode,
        flex: _sizingDraft.flex,
        minWidth: _sizingDraft.minWidth,
        minHeight: _sizingDraft.minHeight,
        maxWidth: _sizingDraft.maxWidth,
        maxHeight: _sizingDraft.maxHeight,
      );
      if (_layoutDraft case final current?) {
        _layoutDraft = SceneLayout(
          direction: direction ?? current.direction,
          padding: current.padding,
          gap: current.gap,
          mainAlignment: mainAlignment ?? current.mainAlignment,
          crossAlignment: crossAlignment ?? current.crossAlignment,
          clip: clip ?? current.clip,
          wrap: wrap ?? current.wrap,
        );
      }
    } finally {
      _updatingFields = false;
    }
    _markDraftChanged(forceNotify: true);
  }

  void updateMotion(SceneMotionPreset motion) {
    if (motion == _motion) return;
    _motion = motion;
    _markDraftChanged(forceNotify: true);
  }

  void updateCustomMotionCurve(bool enabled) {
    if (enabled == _hasCustomMotionCurve) return;
    _hasCustomMotionCurve = enabled;
    _markDraftChanged(forceNotify: true);
  }

  void resetScale() {
    getField('Scale X').text = '1.0';
    getField('Scale Y').text = '1.0';
  }

  void discardDraft() => resetNode(_node);

  void showError(String error) {
    _error = error;
    notifyListeners();
  }

  // Drag values are transient, not inspector drafts. Suppress draft
  // tracking and update only changed inputs, avoiding a rebuild of
  // every inspector section on each move.
  void updatePreviewNode(SceneNode node) {
    _updatingFields = true;
    try {
      for (final entry in _getPreviewValues(node).entries) {
        final field = getField(entry.key);
        final text = _getFieldText(entry.key, entry.value);
        if (field.text != text) field.text = text;
      }
    } finally {
      _updatingFields = false;
    }
  }

  Map<String, double> _getLayoutValues(SceneRect rect) => {
    'X': rect.x * _getLayoutFactor('X'),
    'Y': rect.y * _getLayoutFactor('Y'),
    'Width': rect.width * _getLayoutFactor('Width'),
    'Height': rect.height * _getLayoutFactor('Height'),
  };

  Map<String, double> _getPreviewValues(SceneNode node) => {
    ..._getLayoutValues(node.rect),
    'Scale X': node.transform.scaleX,
    'Scale Y': node.transform.scaleY,
    'Rotate X': node.transform.rotationX,
    'Rotate Y': node.transform.rotationY,
    'Rotate Z': node.transform.rotationZ,
  };

  double _getLayoutFactor(String label) {
    if (_layoutUnit == StudioLayoutUnit.percent) return 100;
    return switch (label) {
      'X' || 'Width' => _canvas.referenceWidth.toDouble(),
      'Y' || 'Height' => _canvas.referenceHeight.toDouble(),
      _ => throw ArgumentError.value(label, 'label'),
    };
  }

  String _getFieldText(String label, Object value) =>
      _layoutFields.contains(label)
      ? (value as double).toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '')
      : '$value';

  void updateLayoutUnit(StudioLayoutUnit unit) {
    if (unit == _layoutUnit) return;
    try {
      final rect = _getDraftRect();
      _layoutUnit = unit;
      _updatingFields = true;
      try {
        for (final entry in _getLayoutValues(rect).entries) {
          getField(entry.key).text = _getFieldText(entry.key, entry.value);
        }
      } finally {
        _updatingFields = false;
      }
      notifyListeners();
    } on FormatException catch (error) {
      showError(error.message);
    }
  }

  void _setFieldValue(String key, Object value) {
    final controller = _fields.putIfAbsent(key, () {
      return TextEditingController()..addListener(() => _onFieldChanged(key));
    });
    controller.text = _getFieldText(key, value);
  }

  Map<String, Object> _getCommittedBaseValues(SceneNode node) {
    final transform = node.transform;
    final timing = node.motionTiming;
    final curve = timing.curve ?? _defaultMotionCurve;
    return {
      ..._getPreviewValues(node),
      'Depth': node.z,
      'Paint order': node.renderOrder,
      'Focus order': node.focusOrder,
      'Translate X': transform.translateX,
      'Translate Y': transform.translateY,
      'Pivot X': transform.pivotX,
      'Pivot Y': transform.pivotY,
      'Perspective': transform.perspective,
      'Duration ms': timing.durationMs?.toString() ?? '',
      'Delay ms': '${timing.delayMs}',
      'Bezier X1': '${curve.x1}',
      'Bezier Y1': '${curve.y1}',
      'Bezier X2': '${curve.x2}',
      'Bezier Y2': '${curve.y2}',
      'Properties': const JsonEncoder.withIndent('  ').convert(node.properties),
    };
  }

  Map<String, String> _getCommittedRuleValues(SceneNode node) {
    final rule = _editingBreakpoint < 0
        ? null
        : node.breakpoints[_editingBreakpoint];
    final ruleSizing = rule?.sizing ?? node.sizing;
    final ruleLayout = rule?.layout ?? node.layout;
    return {
      'Fixed width': ruleSizing.width?.toString() ?? '',
      'Fixed height': ruleSizing.height?.toString() ?? '',
      'Min width': '${ruleSizing.minWidth}',
      'Min height': '${ruleSizing.minHeight}',
      'Max width': ruleSizing.maxWidth?.toString() ?? '',
      'Max height': ruleSizing.maxHeight?.toString() ?? '',
      'Flex': '${ruleSizing.flex}',
      'Padding': '${ruleLayout?.padding ?? 0}',
      'Gap': '${ruleLayout?.gap ?? 0}',
      'Viewport ≥ px': '${rule?.minWidth ?? 640}',
    };
  }

  void _syncActiveRuleDraft(SceneNode node) {
    final rule = _editingBreakpoint < 0
        ? null
        : node.breakpoints[_editingBreakpoint];
    _sizingDraft = rule?.sizing ?? node.sizing;
    _layoutDraft = rule?.layout ?? node.layout;
    for (final entry in _getCommittedRuleValues(node).entries) {
      _setFieldValue(entry.key, entry.value);
    }
  }

  static bool _isLayoutRuleField(String label) => switch (label) {
    'Fixed width' ||
    'Fixed height' ||
    'Min width' ||
    'Min height' ||
    'Max width' ||
    'Max height' ||
    'Flex' ||
    'Padding' ||
    'Gap' ||
    'Viewport ≥ px' => true,
    _ => false,
  };

  bool _isModifiedFromCommitted() {
    if (_motion != _node.motion ||
        _hasCustomMotionCurve != (_node.motionTiming.curve != null)) {
      return true;
    }
    final rule = editingBreakpointRule;
    final committedSizing = rule?.sizing ?? _node.sizing;
    final committedLayout = rule?.layout ?? _node.layout;
    if (_sizingDraft.widthMode != committedSizing.widthMode ||
        _sizingDraft.heightMode != committedSizing.heightMode ||
        _layoutDraft?.direction != committedLayout?.direction ||
        _layoutDraft?.mainAlignment != committedLayout?.mainAlignment ||
        _layoutDraft?.crossAlignment != committedLayout?.crossAlignment ||
        _layoutDraft?.clip != committedLayout?.clip ||
        _layoutDraft?.wrap != committedLayout?.wrap) {
      return true;
    }
    for (final entry in _getCommittedBaseValues(_node).entries) {
      if (getField(entry.key).text != _getFieldText(entry.key, entry.value)) {
        return true;
      }
    }
    for (final entry in _getCommittedRuleValues(_node).entries) {
      if (getField(entry.key).text != entry.value) {
        return true;
      }
    }
    return false;
  }

  void resetNode(SceneNode node, {SceneCanvas? canvas}) {
    _updatingFields = true;
    try {
      if (!_initialized ||
          _node.id != node.id ||
          _editingBreakpoint >= node.breakpoints.length) {
        _editingBreakpoint = -1;
      }
      _node = node;
      _initialized = true;
      if (canvas != null) _canvas = canvas;
      for (final entry in _getCommittedBaseValues(node).entries) {
        _setFieldValue(entry.key, entry.value);
      }
      _syncActiveRuleDraft(node);
      _motion = node.motion;
      _hasCustomMotionCurve = node.motionTiming.curve != null;
      _lastEditedField = null;
      _error = null;
      _hasDraft = false;
    } finally {
      _updatingFields = false;
    }
    notifyListeners();
  }

  double _getNumber(String label) =>
      getFiniteNumberInput(label, getField(label).text);

  double? _getOptionalDimension(String label) {
    final raw = getField(label).text.trim();
    return raw.isEmpty ? null : getFiniteNumberInput(label, raw);
  }

  int _getInteger(String label) => getIntegerInput(label, getField(label).text);

  int? _getOptionalInteger(String label) {
    final raw = getField(label).text;
    return raw.isEmpty ? null : getIntegerInput(label, raw);
  }

  void _validateField(String label) {
    switch (label) {
      case 'X':
      case 'Y':
      case 'Width':
      case 'Height':
      case 'Translate X':
      case 'Translate Y':
      case 'Scale X':
      case 'Scale Y':
      case 'Rotate X':
      case 'Rotate Y':
      case 'Rotate Z':
      case 'Pivot X':
      case 'Pivot Y':
      case 'Perspective':
      case 'Min width':
      case 'Min height':
      case 'Flex':
        _getNumber(label);
      case 'Bezier X1':
      case 'Bezier Y1':
      case 'Bezier X2':
      case 'Bezier Y2':
        if (_hasCustomMotionCurve) _getNumber(label);
      case 'Padding':
      case 'Gap':
        if (_layoutDraft != null) _getNumber(label);
      case 'Viewport ≥ px':
        if (_editingBreakpoint >= 0) _getNumber(label);
      case 'Fixed width':
      case 'Fixed height':
      case 'Max width':
      case 'Max height':
        _getOptionalDimension(label);
      case 'Depth':
      case 'Paint order':
      case 'Focus order':
      case 'Delay ms':
        _getInteger(label);
      case 'Duration ms':
        _getOptionalInteger(label);
      case 'Properties':
        _getValidatedProperties();
    }
  }

  SceneNode getUpdatedNode() {
    if (_lastEditedField case final edited?) {
      _validateField(edited);
    }
    final updatedSizing = _getDraftSizing();
    final updatedLayout = _getDraftLayout();
    final updatedBreakpoints = _editingBreakpoint < 0
        ? _node.breakpoints
        : ([..._node.breakpoints]
            ..[_editingBreakpoint] = SceneBreakpoint(
              minWidth: _getNumber('Viewport ≥ px'),
              sizing: updatedSizing,
              layout: updatedLayout,
            ));
    return _node.copyWith(
      rect: _getDraftRect(),
      z: _getInteger('Depth'),
      renderOrder: _getInteger('Paint order'),
      focusOrder: _getInteger('Focus order'),
      sizing: _editingBreakpoint < 0 ? updatedSizing : _node.sizing,
      layout: _editingBreakpoint < 0 ? updatedLayout : _node.layout,
      breakpoints: updatedBreakpoints,
      motion: _motion,
      motionTiming: _getDraftMotionTiming(),
      transform: _getDraftTransform(),
      properties: _getValidatedProperties(),
    );
  }

  SceneSizing _getDraftSizing() => SceneSizing(
    width: _getOptionalDimension('Fixed width'),
    height: _getOptionalDimension('Fixed height'),
    widthMode: _sizingDraft.widthMode,
    heightMode: _sizingDraft.heightMode,
    flex: _getNumber('Flex'),
    minWidth: _getNumber('Min width'),
    minHeight: _getNumber('Min height'),
    maxWidth: _getOptionalDimension('Max width'),
    maxHeight: _getOptionalDimension('Max height'),
  );

  SceneLayout? _getDraftLayout() => switch (_layoutDraft) {
    null => null,
    final current => SceneLayout(
      direction: current.direction,
      padding: _getNumber('Padding'),
      gap: _getNumber('Gap'),
      mainAlignment: current.mainAlignment,
      crossAlignment: current.crossAlignment,
      clip: current.clip,
      wrap: current.wrap,
    ),
  };

  SceneMotionTiming _getDraftMotionTiming() => SceneMotionTiming(
    durationMs: _getOptionalInteger('Duration ms'),
    delayMs: _getInteger('Delay ms'),
    curve: _hasCustomMotionCurve
        ? SceneCubicBezier(
            _getNumber('Bezier X1'),
            _getNumber('Bezier Y1'),
            _getNumber('Bezier X2'),
            _getNumber('Bezier Y2'),
          )
        : null,
  );

  double _getLayoutNumber(String label, double source) {
    final factor = _getLayoutFactor(label);
    // Formatting is presentation only: untouched geometry retains its full
    // precision when an unrelated property is edited or the units change.
    if (getField(label).text == _getFieldText(label, source * factor)) {
      return source;
    }
    return _getNumber(label) / factor;
  }

  SceneRect _getDraftRect() => SceneRect(
    x: _getLayoutNumber('X', _node.rect.x),
    y: _getLayoutNumber('Y', _node.rect.y),
    width: _getLayoutNumber('Width', _node.rect.width),
    height: _getLayoutNumber('Height', _node.rect.height),
  );

  SceneTransform _getDraftTransform() => SceneTransform(
    translateX: _getNumber('Translate X'),
    translateY: _getNumber('Translate Y'),
    scaleX: _getNumber('Scale X'),
    scaleY: _getNumber('Scale Y'),
    rotationX: _getNumber('Rotate X'),
    rotationY: _getNumber('Rotate Y'),
    rotationZ: _getNumber('Rotate Z'),
    pivotX: _getNumber('Pivot X'),
    pivotY: _getNumber('Pivot Y'),
    perspective: _getNumber('Perspective'),
  );

  void updateProperty(String name, String value) {
    final properties = getPropertiesDraft();
    if (properties[name] == value) return;
    properties[name] = value;
    getField('Properties').text = const JsonEncoder.withIndent('  ')
        .convert(properties);
  }

  Map<String, String> getPropertiesDraft() {
    final properties = jsonDecode(getField('Properties').text);
    if (properties is! Map<String, dynamic> ||
        properties.values.any((value) => value is! String)) {
      throw const FormatException(
        'Properties must be an object of non-empty strings.',
      );
    }
    return properties.cast<String, String>();
  }

  Map<String, String> _getValidatedProperties() {
    final properties = getPropertiesDraft();
    if (properties.values.any((value) => value.isEmpty)) {
      throw const FormatException(
        'Properties must be an object of non-empty strings.',
      );
    }
    return properties;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
