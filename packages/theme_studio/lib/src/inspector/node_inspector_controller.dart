import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:scene/scene.dart';

import 'studio_form_values.dart';

enum StudioLayoutUnit { pixels, percent }

const _layoutFields = {'X', 'Y', 'Width', 'Height'};

/// Owns drafts independently of the inspector widget's mount lifecycle. The
/// editor commits them at document-command boundaries; the view only edits
/// fields and observes validation results.
class NodeInspectorController extends ChangeNotifier {
  NodeInspectorController(SceneNode node, this._canvas) {
    resetNode(node);
  }

  final _fields = <String, TextEditingController>{};
  late SceneNode _node;
  SceneCanvas _canvas;
  StudioLayoutUnit _layoutUnit = StudioLayoutUnit.pixels;
  late SceneMotionPreset _motion;
  String? _error;
  bool _hasDraft = false;
  bool _updatingFields = false;

  SceneNode get node => _node;
  SceneMotionPreset get motion => _motion;
  String? get error => _error;
  bool get hasDraft => _hasDraft;
  StudioLayoutUnit get layoutUnit => _layoutUnit;
  TextEditingController getField(String label) => _fields[label]!;

  void _markDraftChanged() {
    if (_updatingFields || _hasDraft) return;
    _hasDraft = true;
    notifyListeners();
  }

  void updateMotion(SceneMotionPreset motion) {
    if (motion == _motion) return;
    _motion = motion;
    _hasDraft = true;
    notifyListeners();
  }

  void resetScale() {
    getField('Scale X').text = '1.0';
    getField('Scale Y').text = '1.0';
  }

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

  void resetNode(SceneNode node, {SceneCanvas? canvas}) {
    _updatingFields = true;
    try {
      _node = node;
      if (canvas != null) _canvas = canvas;
      final transform = node.transform;
      final values = <String, Object>{
        ..._getPreviewValues(node),
        'Depth': node.z,
        'Paint order': node.renderOrder,
        'Focus order': node.focusOrder,
        'Translate X': transform.translateX,
        'Translate Y': transform.translateY,
        'Pivot X': transform.pivotX,
        'Pivot Y': transform.pivotY,
        'Perspective': transform.perspective,
        'Properties': const JsonEncoder.withIndent('  ').convert(node.properties),
      };
      for (final entry in values.entries) {
        final controller = _fields.putIfAbsent(entry.key, () {
          return TextEditingController()..addListener(_markDraftChanged);
        });
        controller.text = _getFieldText(entry.key, entry.value);
      }
      _motion = node.motion;
      _error = null;
      _hasDraft = false;
    } finally {
      _updatingFields = false;
    }
    notifyListeners();
  }

  double _getNumber(String label) =>
      getFiniteNumberInput(label, getField(label).text);

  int _getInteger(String label) => getIntegerInput(label, getField(label).text);

  SceneNode getUpdatedNode() => _node.copyWith(
    rect: _getDraftRect(),
    z: _getInteger('Depth'),
    renderOrder: _getInteger('Paint order'),
    focusOrder: _getInteger('Focus order'),
    motion: _motion,
    transform: _getDraftTransform(),
    properties: _getValidatedProperties(),
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
