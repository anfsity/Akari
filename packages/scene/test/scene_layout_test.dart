import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

SceneDocument document(List<SceneNode> nodes) => SceneDocument(
  id: 'layout',
  version: currentSceneVersion,
  canvas: const SceneCanvas(),
  background: const SceneBackground(kind: SceneBackgroundKind.solid),
  nodes: nodes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'breakpoints, constraints, fill and wrapping share viewport geometry',
    () {
      final scene = document([
        const SceneNode(
          id: 'frame',
          componentId: 'frame',
          rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
          layout: SceneLayout(
            direction: SceneLayoutDirection.row,
            gap: 10,
            wrap: true,
          ),
          breakpoints: [
            SceneBreakpoint(
              minWidth: 800,
              layout: SceneLayout(
                direction: SceneLayoutDirection.column,
                gap: 5,
              ),
            ),
          ],
        ),
        for (var i = 0; i < 3; i++)
          SceneNode(
            id: 'item$i',
            componentId: 'shape',
            parentId: 'frame',
            rect: const SceneRect(x: 0, y: 0, width: .1, height: .1),
            sizing: const SceneSizing(
              width: 200,
              height: 40,
              minWidth: 100,
              maxWidth: 240,
            ),
          ),
      ]);
      final narrow = calculateSceneLayout(
        document: scene,
        size: const Size(450, 300),
      );
      expect(narrow['item1']!.rect.top, 0);
      expect(narrow['item2']!.rect, const Rect.fromLTWH(0, 50, 200, 40));
      final wide = calculateSceneLayout(
        document: scene,
        size: const Size(900, 300),
      );
      expect(wide['item2']!.rect, const Rect.fromLTWH(0, 90, 200, 40));
      final filled = scene.copyWith(
        nodes: [
          scene.nodes.first.copyWith(
            breakpoints: [],
            layout: const SceneLayout(direction: SceneLayoutDirection.row),
          ),
          scene.nodes[1].copyWith(
            sizing: const SceneSizing(
              widthMode: SceneSizeMode.fill,
              minWidth: 100,
              maxWidth: 300,
              height: 40,
            ),
          ),
        ],
      );
      expect(
        calculateSceneLayout(
          document: filled,
          size: const Size(900, 300),
        )['item0']!.rect.width,
        300,
      );
    },
  );
  test('hug text and frames measure real content and constrain it', () {
    final scene = document(const [
      SceneNode(
        id: 'frame',
        componentId: 'frame',
        rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
        layout: SceneLayout(
          direction: SceneLayoutDirection.row,
          padding: 10,
          gap: 5,
        ),
        sizing: SceneSizing(
          widthMode: SceneSizeMode.hug,
          heightMode: SceneSizeMode.hug,
        ),
      ),
      SceneNode(
        id: 'label',
        componentId: 'text',
        parentId: 'frame',
        primitive: ScenePrimitive.text,
        rect: SceneRect(x: 0, y: 0, width: .1, height: .1),
        properties: {'text': 'Measure me'},
        sizing: SceneSizing(
          widthMode: SceneSizeMode.hug,
          heightMode: SceneSizeMode.hug,
        ),
      ),
    ]);
    final geometry = calculateSceneLayout(
      document: scene,
      size: const Size(600, 400),
    );
    expect(geometry['label']!.rect.width, greaterThan(60));
    expect(
      geometry['frame']!.rect.width,
      closeTo(geometry['label']!.rect.width + 20, .001),
    );
    expect(
      geometry['frame']!.rect.height,
      closeTo(geometry['label']!.rect.height + 20, .001),
    );
  });

  test('nested frames resolve parent coordinates and ancestor transforms', () {
    final scene = document(const [
      SceneNode(
        id: 'frame',
        componentId: 'frame',
        rect: SceneRect(x: .1, y: .1, width: .5, height: .5),
        layout: SceneLayout(),
        transform: SceneTransform(translateX: 20),
      ),
      SceneNode(
        id: 'child',
        componentId: 'text',
        parentId: 'frame',
        rect: SceneRect(x: .2, y: .2, width: .5, height: .5),
      ),
    ]);
    final geometry = calculateSceneLayout(
      document: scene,
      size: const Size(1000, 600),
    );
    expect(geometry['child']!.rect, const Rect.fromLTWH(100, 60, 250, 150));
    expect(geometry['child']!.bounds, const Rect.fromLTWH(220, 120, 250, 150));
  });

  test(
    'row preserves fixed sizes and distributes remaining space on resize',
    () {
      final scene = document(const [
        SceneNode(
          id: 'frame',
          componentId: 'frame',
          rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
          layout: SceneLayout(
            direction: SceneLayoutDirection.row,
            padding: 20,
            gap: 10,
            crossAlignment: SceneCrossAlignment.center,
          ),
        ),
        SceneNode(
          id: 'fixed',
          componentId: 'text',
          parentId: 'frame',
          rect: SceneRect(x: 0, y: 0, width: .1, height: .1),
          sizing: SceneSizing(width: 120, height: 60),
        ),
        SceneNode(
          id: 'flex',
          componentId: 'text',
          parentId: 'frame',
          rect: SceneRect(x: 0, y: 0, width: .1, height: .1),
          sizing: SceneSizing(height: 60, flex: 1),
        ),
      ]);
      for (final width in [400.0, 1000.0]) {
        final geometry = calculateSceneLayout(
          document: scene,
          size: Size(width, 200),
        );
        expect(geometry['fixed']!.rect, const Rect.fromLTWH(20, 70, 120, 60));
        expect(geometry['flex']!.rect, Rect.fromLTWH(150, 70, width - 170, 60));
      }
    },
  );

  test('column handles padding, stretch and interactive minimums', () {
    final scene = document(const [
      SceneNode(
        id: 'frame',
        componentId: 'frame',
        rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
        layout: SceneLayout(
          direction: SceneLayoutDirection.column,
          padding: 10,
          gap: 8,
          crossAlignment: SceneCrossAlignment.stretch,
        ),
      ),
      SceneNode(
        id: 'input',
        componentId: 'input',
        parentId: 'frame',
        interactive: true,
        rect: SceneRect(x: 0, y: 0, width: .1, height: .1),
      ),
    ]);
    final geometry = calculateSceneLayout(
      document: scene,
      size: const Size(300, 200),
    );
    expect(geometry['input']!.rect, const Rect.fromLTWH(10, 10, 280, 44));
  });
}
