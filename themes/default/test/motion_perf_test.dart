import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/terrace_visuals.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  for (final preset in [
    SceneMotionPreset.fadeSlide,
    SceneMotionPreset.fadeScale,
  ]) {
    testWidgets('$preset reuses static painting while moving', (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 420),
      );
      addTearDown(controller.dispose);
      final painter = _PaintCounter();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 80,
              child: Builder(
                builder: (context) => const TerraceEntranceMotion().build(
                  context,
                  (
                    preset: preset,
                    duration: controller.duration!,
                    curve: Curves.linear,
                    reducedMotion: false,
                  ),
                  controller,
                  CustomPaint(painter: painter),
                ),
              ),
            ),
          ),
        ),
      );
      controller.forward();
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(painter.paints, greaterThan(0));
      expect(painter.paints, lessThanOrEqualTo(2));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a shake reuses the credential surface painting', (tester) async {
    final painter = _PaintCounter();
    const prompt = (
      mode: AuthMode.prompting,
      selectedUser: null,
      prompt: (kind: PromptKind.secret, text: 'Password'),
      error: null,
      promptError: null,
    );
    final surface = CustomPaint(painter: painter);
    Future<void> update(AuthPromptSlots auth) => tester.pumpWidget(
      MaterialApp(
        theme: buildDefaultTheme().materialTheme,
        home: Center(
          child: SizedBox(
            width: 300,
            height: 60,
            child: TerraceCredentialFeedback(auth: auth, child: surface),
          ),
        ),
      ),
    );
    await update(prompt);
    await tester.pumpAndSettle();
    await update((
      mode: prompt.mode,
      selectedUser: null,
      prompt: prompt.prompt,
      error: null,
      promptError: 'Incorrect password',
    ));
    final before = painter.paints;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(painter.paints - before, lessThanOrEqualTo(1));
    await tester.pumpAndSettle();
  });
}

class _PaintCounter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
