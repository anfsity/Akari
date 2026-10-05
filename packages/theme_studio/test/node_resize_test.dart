import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:theme_studio/src/node_resize.dart';

const _canvas = Size(1000, 800);
const _source = SceneNode(
  id: 'label',
  componentId: 'label',
  rect: SceneRect(x: 0.2, y: 0.2, width: 0.3, height: 0.25),
);

Offset _getAnchor(SceneNode node, Alignment alignment) {
  final rect = sceneNodeRect(
    node: node,
    sceneSize: _canvas,
    safeArea: EdgeInsets.zero,
    minHitTarget: 44,
  );
  return rect.topLeft +
      MatrixUtils.transformPoint(
        sceneNodeTransformMatrix(node.transform, rect.size),
        alignment.alongSize(rect.size),
      );
}

void main() {
  for (final handle in NodeResizeHandle.values) {
    test('${handle.name} resizes layout and anchors the opposite edge', () {
      final resized = calculateResizedNode(
        source: _source,
        canvasSize: _canvas,
        handle: handle,
        delta: Offset(handle.alignment.x * 60, handle.alignment.y * 40),
        lockAspectRatio: false,
        minHitTarget: 44,
      );
      expect(
        resized.rect.width,
        closeTo(handle.alignment.x == 0 ? 0.3 : 0.36, 1e-9),
      );
      expect(
        resized.rect.height,
        closeTo(handle.alignment.y == 0 ? 0.25 : 0.3, 1e-9),
      );
      final anchor = Alignment(-handle.alignment.x, -handle.alignment.y);
      expect(
        (_getAnchor(resized, anchor) - _getAnchor(_source, anchor)).distance,
        lessThan(1e-8),
      );
      expect(resized.transform, same(_source.transform));
    });
  }

  test('resize follows rotated, mirrored and perspective editing planes', () {
    for (final transform in [
      const SceneTransform(
        rotationZ: 35,
        scaleX: -1.2,
        scaleY: 0.8,
        pivotX: 0.2,
      ),
      const SceneTransform(
        rotationX: 20,
        rotationY: 25,
        rotationZ: 10,
        perspective: 0.001,
      ),
    ]) {
      final source = _source.copyWith(transform: transform);
      final rectSize = Size(
        source.rect.width * _canvas.width,
        source.rect.height * _canvas.height,
      );
      final matrix = sceneNodeTransformMatrix(transform, rectSize);
      final delta =
          MatrixUtils.transformPoint(
            matrix,
            Offset(rectSize.width + 30, rectSize.height + 20),
          ) -
          MatrixUtils.transformPoint(matrix, rectSize.bottomRight(Offset.zero));
      final resized = calculateResizedNode(
        source: source,
        canvasSize: _canvas,
        handle: NodeResizeHandle.bottomRight,
        delta: delta,
        lockAspectRatio: false,
        minHitTarget: 44,
      );
      expect(resized.rect.width, closeTo(0.33, 1e-8));
      expect(resized.rect.height, closeTo(0.275, 1e-8));
      expect(
        (_getAnchor(resized, Alignment.topLeft) -
                _getAnchor(source, Alignment.topLeft))
            .distance,
        lessThan(1e-8),
      );
      expect(resized.transform, same(transform));
    }
  });

  test('aspect lock survives canvas bounds and shrinking past the anchor', () {
    for (final delta in [const Offset(3000, 500), const Offset(-3000, -3000)]) {
      final resized = calculateResizedNode(
        source: _source,
        canvasSize: _canvas,
        handle: NodeResizeHandle.bottomRight,
        delta: delta,
        lockAspectRatio: true,
        minHitTarget: 44,
      );
      expect(resized.rect.isNormalized, isTrue);
      expect(resized.rect.width / resized.rect.height, closeTo(1.2, 1e-8));
      expect(resized.rect.width * _canvas.width, greaterThanOrEqualTo(1));
      expect(
        (_getAnchor(resized, Alignment.topLeft) -
                _getAnchor(_source, Alignment.topLeft))
            .distance,
        lessThan(1e-8),
      );
    }
  });

  test('resize snaps the dragged edge to the canvas grid', () {
    final resized = calculateResizedNode(
      source: _source,
      canvasSize: _canvas,
      handle: NodeResizeHandle.right,
      delta: const Offset(33, 0),
      lockAspectRatio: false,
      minHitTarget: 44,
      gridSize: 20,
    );
    expect(
      (resized.rect.x + resized.rect.width) * _canvas.width,
      closeTo(540, 1e-8),
    );
    expect(resized.rect.height, _source.rect.height);
  });

  test('singular projections do not expose resize handles', () {
    expect(
      hasResizableProjection(
        _source.copyWith(transform: const SceneTransform(scaleX: 0)),
        const Size(300, 200),
      ),
      isFalse,
    );
    expect(
      hasResizableProjection(
        _source.copyWith(transform: const SceneTransform(rotationY: 90)),
        const Size(300, 200),
      ),
      isFalse,
    );
  });
}
