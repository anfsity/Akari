import 'package:mozais_scene_schema/mozais_scene_schema.dart';
import 'package:test/test.dart';

void main() {
  test('copyWith replaces only the provided fields', () {
    const node = SceneNode(
      id: 'panel',
      kind: SceneNodeKind.glassPanel,
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      z: 1,
      motion: SceneMotionPreset.fade,
      visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
      action: SceneAction.selectUser,
    );

    final moved = node.copyWith(
      rect: node.rect.copyWith(x: 0.4),
      transform: node.transform.copyWith(rotationZ: 15),
    );

    expect(moved.rect.x, 0.4);
    expect(moved.rect.y, 0.1);
    expect(moved.transform.rotationZ, 15);
    expect(moved.transform.scaleX, 1);
    expect(moved.kind, SceneNodeKind.glassPanel);
    expect(moved.z, 1);
    expect(moved.motion, SceneMotionPreset.fade);
    expect(moved.visibleWhen, isNotNull);
    expect(moved.action, SceneAction.selectUser);
  });

  test('copyWith can clear a nullable condition and action', () {
    const node = SceneNode(
      id: 'panel',
      kind: SceneNodeKind.glassPanel,
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
      action: SceneAction.selectUser,
    );

    final cleared = node.copyWith(visibleWhen: null, action: null);

    expect(cleared.visibleWhen, isNull);
    expect(cleared.action, isNull);
  });
}
