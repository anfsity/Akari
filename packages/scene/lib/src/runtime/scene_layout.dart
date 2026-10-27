import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

import 'node_transform.dart';
import 'scene_font.dart';

/// Parent-local geometry and the effective responsive node share one resolution.
class SceneNodeGeometry {
  const SceneNodeGeometry({
    required this.node,
    required this.rect,
    required this.worldTransform,
  });
  final SceneNode node;
  final Rect rect;
  final Matrix4 worldTransform;
  Rect get bounds =>
      MatrixUtils.transformRect(worldTransform, Offset.zero & rect.size);
}

List<List<SceneNode>> _getFlowLines(
  List<SceneNode> nodes,
  SceneLayout layout,
  double main,
  double Function(SceneNode) extent,
) {
  final lines = <List<SceneNode>>[];
  var line = <SceneNode>[];
  var used = 0.0;
  for (final node in nodes) {
    final size = extent(node);
    if (layout.wrap && line.isNotEmpty && used + layout.gap + size > main) {
      lines.add(line);
      line = [];
      used = 0;
    }
    used += (line.isEmpty ? 0 : layout.gap) + size;
    line.add(node);
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

/// Shared by runtime and authoring. Hug frames measure children against the
/// available space, then place those measured sizes without a percentage loop.
/// Theme components have no portable intrinsic contract; hug is for frames and
/// primitive text. Interactive minimums take precedence over authored maxima.
Map<String, SceneNodeGeometry> calculateSceneLayout({
  required SceneDocument document,
  required Size size,
  EdgeInsets safeArea = EdgeInsets.zero,
  double minHitTarget = 44,
  Map<String, String>? fontFamilies,
}) {
  final result = <String, SceneNodeGeometry>{};
  final hugMeasurements = <String, Size>{};
  final children = <String?, List<SceneNode>>{};
  for (final original in document.paintOrder) {
    final node = getSceneNodeForWidth(original, size.width);
    children.putIfAbsent(node.parentId, () => []).add(node);
  }
  Size constrain(SceneNode node, Size value) {
    final s = node.sizing;
    final hit = node.interactive ? minHitTarget : 0.0;
    return Size(
      math.max(
        hit,
        value.width.clamp(s.minWidth, s.maxWidth ?? double.infinity),
      ),
      math.max(
        hit,
        value.height.clamp(s.minHeight, s.maxHeight ?? double.infinity),
      ),
    );
  }

  Size measure(SceneNode node, Size available) {
    final s = node.sizing;
    var width =
        s.width ??
        (s.widthMode == SceneSizeMode.fill
            ? available.width
            : available.width * node.rect.width);
    var height =
        s.height ??
        (s.heightMode == SceneSizeMode.fill
            ? available.height
            : available.height * node.rect.height);
    if (s.widthMode == SceneSizeMode.hug || s.heightMode == SceneSizeMode.hug) {
      Size natural;
      if (node.primitive == ScenePrimitive.text) {
        final style =
            document.styleTokens[node.styleToken] ?? const SceneStyle();
        final painter =
            TextPainter(
              text: TextSpan(
                text: node.properties['text'] ?? 'Text',
                style: TextStyle(
                  fontSize: style.fontSize == 0 ? 14 : style.fontSize,
                  fontFamily:
                      (fontFamilies ??
                      sceneFontFamilies.value)[style.fontAsset],
                  fontWeight: style.fontWeight == 0
                      ? FontWeight.normal
                      : FontWeight.values[style.fontWeight ~/ 100 - 1],
                  letterSpacing: style.letterSpacing,
                  height: style.lineHeight,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(
              maxWidth: s.widthMode == SceneSizeMode.hug
                  ? s.maxWidth ?? available.width
                  : width,
            );
        natural = painter.size;
        painter.dispose();
      } else {
        final layout = node.layout!;
        final potential = constrain(
          node,
          Size(
            s.widthMode == SceneSizeMode.hug ? available.width : width,
            s.heightMode == SceneSizeMode.hug ? available.height : height,
          ),
        );
        final inner = Size(
          math.max(0, potential.width - layout.padding * 2),
          math.max(0, potential.height - layout.padding * 2),
        );
        hugMeasurements[node.id] = inner;
        final nodes = children[node.id] ?? const <SceneNode>[];
        final sizes = {
          for (final child in nodes) child.id: measure(child, inner),
        };
        var w = 0.0;
        var h = 0.0;
        if (layout.direction == SceneLayoutDirection.absolute) {
          for (final child in nodes) {
            final measured = sizes[child.id]!;
            w = math.max(w, inner.width * child.rect.x + measured.width);
            h = math.max(h, inner.height * child.rect.y + measured.height);
          }
        } else {
          final row = layout.direction == SceneLayoutDirection.row;
          final lines = _getFlowLines(
            nodes,
            layout,
            row ? inner.width : inner.height,
            (child) => row ? sizes[child.id]!.width : sizes[child.id]!.height,
          );
          for (final line in lines) {
            final main = line.fold<double>(
              math.max(0, line.length - 1) * layout.gap,
              (value, child) =>
                  value +
                  (row ? sizes[child.id]!.width : sizes[child.id]!.height),
            );
            final cross = line.fold<double>(
              0,
              (value, child) => math.max(
                value,
                row ? sizes[child.id]!.height : sizes[child.id]!.width,
              ),
            );
            if (row) {
              w = math.max(w, main);
              h += cross;
            } else {
              h = math.max(h, main);
              w += cross;
            }
          }
          final gaps = math.max(0, lines.length - 1) * layout.gap;
          if (row) {
            h += gaps;
          } else {
            w += gaps;
          }
        }
        natural = Size(w + layout.padding * 2, h + layout.padding * 2);
      }
      if (s.widthMode == SceneSizeMode.hug) width = natural.width;
      if (s.heightMode == SceneSizeMode.hug) height = natural.height;
    }
    return constrain(node, Size(width, height));
  }

  void place(
    String? parentId,
    Size parentSize,
    Matrix4 parentTransform,
    SceneLayout layout,
    EdgeInsets insets, {
    Size? measurementSize,
  }) {
    final nodes = children[parentId] ?? const <SceneNode>[];
    final content = Rect.fromLTWH(
      insets.left,
      insets.top,
      math.max(0, parentSize.width - insets.horizontal),
      math.max(0, parentSize.height - insets.vertical),
    );
    final available = measurementSize ?? content.size;
    final sizes = {for (final node in nodes) node.id: measure(node, available)};
    final row = layout.direction == SceneLayoutDirection.row;
    final main = row ? content.width : content.height;
    double mainSize(Size value) => row ? value.width : value.height;
    double crossSize(Size value) => row ? value.height : value.width;
    double flex(SceneNode node) {
      if (node.sizing.flex > 0) return node.sizing.flex;
      final mode = row ? node.sizing.widthMode : node.sizing.heightMode;
      final fixed = row ? node.sizing.width : node.sizing.height;
      return mode == SceneSizeMode.fill && fixed == null ? 1 : 0;
    }

    double minimum(SceneNode node) => math.max(
      row ? node.sizing.minWidth : node.sizing.minHeight,
      node.interactive ? minHitTarget : 0,
    );
    final positions = <String, Rect>{};
    if (layout.direction == SceneLayoutDirection.absolute) {
      for (final node in nodes) {
        positions[node.id] =
            (content.topLeft +
                Offset(
                  available.width * node.rect.x,
                  available.height * node.rect.y,
                )) &
            sizes[node.id]!;
      }
    } else {
      final lines = _getFlowLines(
        nodes,
        layout,
        main,
        (node) => flex(node) > 0 ? minimum(node) : mainSize(sizes[node.id]!),
      );
      var crossCursor = 0.0;
      for (final line in lines) {
        final fixed = line.fold<double>(
          math.max(0, line.length - 1) * layout.gap,
          (sum, node) =>
              sum +
              (flex(node) > 0 ? minimum(node) : mainSize(sizes[node.id]!)),
        );
        final totalFlex = line.fold<double>(0, (sum, node) => sum + flex(node));
        final remaining = math.max(0.0, main - fixed);
        final spare = totalFlex > 0 ? 0.0 : remaining;
        var cursor = switch (layout.mainAlignment) {
          SceneMainAlignment.center => spare / 2,
          SceneMainAlignment.end => spare,
          _ => 0.0,
        };
        final gap =
            layout.gap +
            (layout.mainAlignment == SceneMainAlignment.spaceBetween &&
                    line.length > 1
                ? spare / (line.length - 1)
                : 0);
        final cross = layout.wrap
            ? line.fold<double>(
                0,
                (value, node) => math.max(value, crossSize(sizes[node.id]!)),
              )
            : (row ? content.height : content.width);
        for (final node in line) {
          final natural = sizes[node.id]!;
          final extent = flex(node) > 0
              ? minimum(node) + remaining * flex(node) / totalFlex
              : mainSize(natural);
          final across = layout.crossAlignment == SceneCrossAlignment.stretch
              ? cross
              : crossSize(natural);
          final resolved = constrain(
            node,
            row ? Size(extent, across) : Size(across, extent),
          );
          final offset = switch (layout.crossAlignment) {
            SceneCrossAlignment.center => (cross - crossSize(resolved)) / 2,
            SceneCrossAlignment.end => cross - crossSize(resolved),
            _ => 0.0,
          };
          positions[node.id] =
              (content.topLeft +
                  (row
                      ? Offset(cursor, crossCursor + offset)
                      : Offset(crossCursor + offset, cursor))) &
              resolved;
          cursor += mainSize(resolved) + gap;
        }
        crossCursor += cross + layout.gap;
      }
    }
    for (final node in nodes) {
      final rect = positions[node.id]!;
      final transform = parentTransform.clone()
        ..translateByDouble(rect.left, rect.top, 0, 1)
        ..multiply(sceneNodeTransformMatrix(node.transform, rect.size));
      result[node.id] = SceneNodeGeometry(
        node: node,
        rect: rect,
        worldTransform: transform,
      );
      if (node.layout case final childLayout?) {
        final insets = EdgeInsets.all(childLayout.padding);
        place(
          node.id,
          rect.size,
          transform,
          childLayout,
          insets,
          measurementSize: hugMeasurements[node.id],
        );
      }
    }
  }

  place(
    null,
    size,
    Matrix4.identity(),
    const SceneLayout(),
    document.canvas.useSafeArea ? safeArea : EdgeInsets.zero,
  );
  return result;
}
