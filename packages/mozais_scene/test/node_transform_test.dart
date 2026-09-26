import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  group('sceneNodeRect', () {
    test('maps a normalized rect into scene coordinates', () {
      final rect = sceneNodeRect(
        node: _node(const SceneRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
        sceneSize: const Size(1000, 500),
        safeArea: EdgeInsets.zero,
        minHitTarget: 44,
      );

      expect(rect, const Rect.fromLTWH(100, 100, 300, 200));
    });

    test('expands interactive nodes to the minimum hit target', () {
      final rect = sceneNodeRect(
        node: _node(
          const SceneRect(x: 0, y: 0, width: 0.01, height: 0.01),
          interactive: true,
        ),
        sceneSize: const Size(1000, 500),
        safeArea: EdgeInsets.zero,
        minHitTarget: 44,
      );

      expect(rect.width, 44);
      expect(rect.height, 44);
    });

    test('insets the available area by the safe area', () {
      final rect = sceneNodeRect(
        node: _node(const SceneRect(x: 0, y: 0, width: 1, height: 1)),
        sceneSize: const Size(1000, 500),
        safeArea: const EdgeInsets.all(50),
        minHitTarget: 44,
      );

      expect(rect, const Rect.fromLTWH(50, 50, 900, 400));
    });
  });

  group('sceneNodeTransformMatrix', () {
    test('is the identity for an identity transform', () {
      final matrix = sceneNodeTransformMatrix(
        const SceneTransform(),
        const Size(100, 50),
      );

      expect(matrix, Matrix4.identity());
    });

    test('rotates around the pivot', () {
      final matrix = sceneNodeTransformMatrix(
        const SceneTransform(rotationZ: 90),
        const Size(100, 50),
      );

      final center = MatrixUtils.transformPoint(matrix, const Offset(50, 25));
      expect(center.dx, closeTo(50, 1e-9));
      expect(center.dy, closeTo(25, 1e-9));

      final origin = MatrixUtils.transformPoint(matrix, Offset.zero);
      expect(origin.dx, closeTo(75, 1e-9));
      expect(origin.dy, closeTo(-25, 1e-9));
    });

    test('scales around the pivot', () {
      final matrix = sceneNodeTransformMatrix(
        const SceneTransform(scaleX: 2),
        const Size(100, 50),
      );

      final point = MatrixUtils.transformPoint(matrix, const Offset(100, 25));
      expect(point.dx, closeTo(150, 1e-9));
      expect(point.dy, closeTo(25, 1e-9));
    });

    test('translates in scene units', () {
      final matrix = sceneNodeTransformMatrix(
        const SceneTransform(translateX: 12, translateY: -8),
        const Size(100, 50),
      );

      final point = MatrixUtils.transformPoint(matrix, const Offset(10, 10));
      expect(point.dx, closeTo(22, 1e-9));
      expect(point.dy, closeTo(2, 1e-9));
    });
  });
}

SceneNode _node(
  SceneRect rect, {
  String componentId = 'decoration',
  bool interactive = false,
}) {
  return SceneNode(
    id: 'node',
    componentId: componentId,
    rect: rect,
    interactive: interactive,
  );
}
