import 'dart:convert';

import 'scene_color_codec.dart';
import 'scene_condition.dart';
import 'scene_document.dart';
import 'scene_json_reader.dart';
import 'scene_layout.dart';
import 'scene_motion.dart';
import 'scene_shader.dart';
import 'scene_style.dart';

/// Encodes a scene document into its JSON authoring form.
String encodeSceneDocument(SceneDocument document) {
  return const JsonEncoder.withIndent('  ').convert(_encodeDocument(document));
}

/// Encodes a single scene node into its formatted JSON authoring form.
String encodeSceneNode(SceneNode node) {
  return const JsonEncoder.withIndent('  ').convert(_encodeNode(node));
}

JsonMap _encodeDocument(SceneDocument document) {
  return {
    'id': document.id,
    'version': document.version,
    if (document.guides.isNotEmpty)
      'guides': [
        for (final guide in document.guides)
          {'axis': guide.axis.name, 'position': guide.position},
      ],
    if (document.styleTokens.isNotEmpty)
      'styleTokens': {
        for (final entry in document.styleTokens.entries)
          entry.key: _encodeStyle(entry.value),
      },
    if (document.themeProperties.isNotEmpty)
      'themeProperties': document.themeProperties,
    'canvas': {
      'fit': document.canvas.fit.name,
      'useSafeArea': document.canvas.useSafeArea,
      'referenceWidth': document.canvas.referenceWidth,
      'referenceHeight': document.canvas.referenceHeight,
    },
    'background': _encodeBackground(document.background),
    'nodes': [for (final node in document.nodes) _encodeNode(node)],
  };
}

JsonMap _encodeShader(SceneShader shader) => {
  'asset': shader.asset,
  'uniforms': [
    for (final uniform in shader.uniforms)
      {
        'name': uniform.name,
        'source': uniform.source.name,
        'value': uniform.value,
        'scale': uniform.scale,
      },
  ],
  'textures': [
    for (final texture in shader.textures)
      {'name': texture.name, 'asset': texture.asset},
  ],
};

JsonMap _encodeBackground(SceneBackground background) {
  return {
    'kind': background.kind.name,
    if (background.shader != null) 'shader': _encodeShader(background.shader!),
    if (background.asset != null) 'asset': background.asset,
    'color': encodeSceneColor(background.color),
    'scrimOpacity': background.scrimOpacity,
    'blurSigma': background.blurSigma,
    if (background.rendererId != null) 'rendererId': background.rendererId,
    if (background.parameters.isNotEmpty) 'parameters': background.parameters,
  };
}

JsonMap _encodeNode(SceneNode node) {
  return {
    'id': node.id,
    'component': node.componentId,
    if (node.styleToken != null) 'styleToken': node.styleToken,
    if (node.primitive != null) 'primitive': node.primitive!.name,
    if (node.asset case final asset?)
      'asset': {
        'path': asset.path,
        'kind': asset.kind.name,
        'fit': asset.fit.name,
        if (asset.tint != null) 'tint': encodeSceneColor(asset.tint!),
      },
    if (node.parentId != null) 'parentId': node.parentId,
    if (node.layout case final layout?) 'layout': _encodeLayout(layout),
    'sizing': _encodeSizing(node.sizing),
    if (node.breakpoints.isNotEmpty)
      'breakpoints': [
        for (final rule in node.breakpoints)
          {
            'minWidth': rule.minWidth,
            if (rule.layout != null) 'layout': _encodeLayout(rule.layout!),
            if (rule.sizing != null) 'sizing': _encodeSizing(rule.sizing!),
          },
      ],
    'rect': {
      'x': node.rect.x,
      'y': node.rect.y,
      'width': node.rect.width,
      'height': node.rect.height,
    },
    if (!node.transform.isDefault)
      'transform': _encodeTransform(node.transform),
    if (node.z != 0) 'z': node.z,
    if (node.renderOrder != 0) 'renderOrder': node.renderOrder,
    if (node.focusOrder != 0) 'focusOrder': node.focusOrder,
    if (node.motion != SceneMotionPreset.none) 'motion': node.motion.name,
    if (node.stateEffects.isNotEmpty)
      'stateEffects': {
        for (final entry in node.stateEffects.entries)
          entry.key.name: entry.value.name,
      },
    if (node.tracks.isNotEmpty)
      'tracks': [
        for (final track in node.tracks)
          {
            'property': track.property.name,
            'keyframes': [
              for (final frame in track.keyframes)
                {
                  'timeMs': frame.timeMs,
                  'value': frame.value,
                  'curve': frame.curve.name,
                },
            ],
          },
      ],
    if (node.transitions.isNotEmpty)
      'transitions': [
        for (final rule in node.transitions)
          {
            'source': _encodeCondition(rule.source),
            'target': _encodeCondition(rule.target),
            'effect': rule.effect.name,
            if (!rule.timing.isDefault)
              'timing': _encodeMotionTiming(rule.timing),
          },
      ],
    if (!node.motionTiming.isDefault)
      'motionTiming': _encodeMotionTiming(node.motionTiming),
    if (node.visibleWhen != null)
      'visibleWhen': _encodeCondition(node.visibleWhen!),
    if (node.interactive) 'interactive': true,
    if (node.properties.isNotEmpty) 'properties': node.properties,
  };
}

JsonMap _encodeMotionTiming(SceneMotionTiming timing) => {
  if (timing.durationMs != null) 'durationMs': timing.durationMs,
  'delayMs': timing.delayMs,
  if (timing.curve case final curve?)
    'curve': [curve.x1, curve.y1, curve.x2, curve.y2],
};

JsonMap _encodeStyle(SceneStyle style) => {
  'fill': encodeSceneColor(style.fill),
  if (style.gradientEnd != null)
    'gradientEnd': encodeSceneColor(style.gradientEnd!),
  'gradientAngle': style.gradientAngle,
  'border': encodeSceneColor(style.border),
  'borderWidth': style.borderWidth,
  'radius': style.radius,
  'shadow': encodeSceneColor(style.shadow),
  'shadowBlur': style.shadowBlur,
  'shadowY': style.shadowY,
  'backgroundBlur': style.backgroundBlur,
  if (style.textColor != null) 'textColor': encodeSceneColor(style.textColor!),
  'fontSize': style.fontSize,
  if (style.fontAsset != null) 'fontAsset': style.fontAsset,
  'fontWeight': style.fontWeight,
  if (style.letterSpacing != null) 'letterSpacing': style.letterSpacing,
  if (style.lineHeight != null) 'lineHeight': style.lineHeight,
  'opacity': style.opacity,
};

JsonMap _encodeLayout(SceneLayout layout) => {
  'direction': layout.direction.name,
  'padding': layout.padding,
  'gap': layout.gap,
  'mainAlignment': layout.mainAlignment.name,
  'crossAlignment': layout.crossAlignment.name,
  'clip': layout.clip,
  'wrap': layout.wrap,
};

JsonMap _encodeSizing(SceneSizing sizing) => {
  if (sizing.width != null) 'width': sizing.width,
  if (sizing.height != null) 'height': sizing.height,
  'flex': sizing.flex,
  'widthMode': sizing.widthMode.name,
  'heightMode': sizing.heightMode.name,
  'minWidth': sizing.minWidth,
  'minHeight': sizing.minHeight,
  if (sizing.maxWidth != null) 'maxWidth': sizing.maxWidth,
  if (sizing.maxHeight != null) 'maxHeight': sizing.maxHeight,
};

JsonMap _encodeTransform(SceneTransform transform) {
  return {
    'translateX': transform.translateX,
    'translateY': transform.translateY,
    'scaleX': transform.scaleX,
    'scaleY': transform.scaleY,
    'rotationX': transform.rotationX,
    'rotationY': transform.rotationY,
    'rotationZ': transform.rotationZ,
    'pivotX': transform.pivotX,
    'pivotY': transform.pivotY,
    'perspective': transform.perspective,
  };
}

Object _encodeCondition(SceneCondition condition) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) => predicate.name,
    SceneAll(:final conditions) => {
      'all': [for (final child in conditions) _encodeCondition(child)],
    },
    SceneAny(:final conditions) => {
      'any': [for (final child in conditions) _encodeCondition(child)],
    },
    SceneNot(:final condition) => {'not': _encodeCondition(condition)},
  };
}
