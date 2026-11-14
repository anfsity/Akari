import 'package:scene_schema/scene_schema.dart';
import 'package:test/test.dart';

void main() {
  test('copyWith replaces only the provided fields', () {
    const node = SceneNode(
      id: 'panel',
      componentId: 'glassPanel',
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      z: 1,
      motion: SceneMotionPreset.fade,
      visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
      interactive: true,
    );

    final moved = node.copyWith(
      rect: node.rect.copyWith(x: 0.4),
      transform: node.transform.copyWith(rotationZ: 15),
    );

    expect(moved.rect.x, 0.4);
    expect(moved.rect.y, 0.1);
    expect(moved.transform.rotationZ, 15);
    expect(moved.transform.scaleX, 1);
    expect(moved.componentId, 'glassPanel');
    expect(moved.z, 1);
    expect(moved.motion, SceneMotionPreset.fade);
    expect(moved.visibleWhen, isNotNull);
    expect(moved.interactive, isTrue);
  });

  test('copyWith clears a condition and updates interactivity', () {
    const node = SceneNode(
      id: 'panel',
      componentId: 'glassPanel',
      rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
      interactive: true,
    );

    final cleared = node.copyWith(visibleWhen: null, interactive: false);

    expect(cleared.visibleWhen, isNull);
    expect(cleared.interactive, isFalse);
  });

  test('value equality compares scene models deeply and background clears asset', () {
    const base = SceneBackground(
      kind: SceneBackgroundKind.image,
      asset: 'assets/bg.png',
      rendererId: 'terrace',
      shader: SceneShader(
        asset: 'assets/water.frag',
        uniforms: [SceneShaderUniform(name: 'time', scale: 2)],
        textures: [SceneShaderTexture(name: 'bg', asset: 'assets/bg.png')],
      ),
    );
    expect(
      base,
      equals(
        const SceneBackground(
          kind: SceneBackgroundKind.image,
          asset: 'assets/bg.png',
          rendererId: 'terrace',
          shader: SceneShader(
            asset: 'assets/water.frag',
            uniforms: [SceneShaderUniform(name: 'time', scale: 2)],
            textures: [SceneShaderTexture(name: 'bg', asset: 'assets/bg.png')],
          ),
        ),
      ),
    );
    final cleared = base.copyWith(asset: null, rendererId: null, shader: null);
    expect(cleared.asset, isNull);
    expect(cleared.rendererId, isNull);
    expect(cleared.shader, isNull);
  });
}
