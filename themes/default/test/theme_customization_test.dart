import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

// These decorative nodes must not depend on authentication or host resources.
class _UnusedHost implements GreeterHost {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected host access: ${invocation.memberName}');
}

void main() {
  test('existing scenes validate without changing authored data', () {
    final theme = buildDefaultTheme();
    final encoded = encodeSceneDocument(theme.document);
    theme.componentCatalog.validateDocument(theme.document);
    expect(encodeSceneDocument(theme.document), encoded);
    expect(theme.componentCatalog.components.keys, [
      'terraceLabel',
      'dateTime',
      'terraceClock',
    ]);
  });

  test('unsupported variants fail at the theme document boundary', () {
    final theme = buildDefaultTheme();
    for (final component in ['terraceLabel', 'dateTime', 'terraceClock']) {
      final node = theme.document.nodes.firstWhere(
        (node) => node.componentId == component,
      );
      expect(
        () => buildDefaultTheme(
          document: theme.document.copyWith(
            nodes: [
              node.copyWith(properties: {'variant': 'unsupported'}),
            ],
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Node "${node.id}": Property "variant"'),
          ),
        ),
      );
    }
  });

  testWidgets('saved label configuration renders with the declared defaults', (
    tester,
  ) async {
    final original = buildDefaultTheme();
    final label = original.document.nodes.firstWhere(
      (node) => node.componentId == 'terraceLabel',
    );

    Future<void> renderProperties(Map<String, String> properties) async {
      final saved = encodeSceneDocument(
        original.document.copyWith(
          nodes: [label.copyWith(properties: properties)],
        ),
      );
      final theme = buildDefaultTheme(document: decodeSceneDocument(saved));
      final components = theme.components(
        GreeterThemeContext(
          host: _UnusedHost(),
          tokens: theme.tokens,
          canvas: theme.document.canvas,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.materialTheme,
          home: Builder(
            builder: (context) =>
                components.build(context, theme.document.nodes.single),
          ),
        ),
      );
    }

    await renderProperties({});
    expect(tester.widget<Text>(find.text('Welcome')).style!.fontSize, 11);
    await renderProperties({'text': 'My desktop', 'variant': 'large'});
    expect(tester.widget<Text>(find.text('My desktop')).style!.fontSize, 48);
    await renderProperties({'text': 'My desktop', 'variant': 'regular'});
    expect(tester.widget<Text>(find.text('My desktop')).style!.fontSize, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standby clock styles reopen through the compiled renderer', (
    tester,
  ) async {
    final original = buildDefaultTheme();
    final clock = original.document.nodes.firstWhere(
      (node) => node.componentId == 'terraceClock',
    );
    for (final variant in [null, 'display', 'stacked', 'compact']) {
      final theme = buildDefaultTheme(
        document: decodeSceneDocument(
          encodeSceneDocument(
            original.document.copyWith(
              nodes: [
                clock.copyWith(properties: {'variant': ?variant}),
              ],
            ),
          ),
        ),
      );
      final components = theme.components(
        GreeterThemeContext(
          host: _UnusedHost(),
          tokens: theme.tokens,
          canvas: theme.document.canvas,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.materialTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 160,
                child: Builder(
                  builder: (context) =>
                      components.build(context, theme.document.nodes.single),
                ),
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(
        text.data,
        matches(variant == 'stacked' ? r'^\d{2}\n\d{2}$' : r'^\d{2}:\d{2}$'),
      );
      expect(text.style!.fontSize, variant == 'compact' ? 72 : 132);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'saved clock choices render through the shared component factory',
    (tester) async {
      final original = buildDefaultTheme();
      final clock = original.document.nodes.firstWhere(
        (node) => node.componentId == 'dateTime',
      );
      for (final variant in [null, 'date', 'time']) {
        final document = decodeSceneDocument(
          encodeSceneDocument(
            original.document.copyWith(
              nodes: [
                clock.copyWith(properties: {'variant': ?variant}),
              ],
            ),
          ),
        );
        final theme = buildDefaultTheme(document: document);
        final components = theme.components(
          GreeterThemeContext(
            host: _UnusedHost(),
            tokens: theme.tokens,
            canvas: document.canvas,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.materialTheme,
            home: Builder(
              builder: (context) =>
                  components.build(context, document.nodes.single),
            ),
          ),
        );
        expect(
          find.textContaining(
            variant == 'time'
                ? RegExp(r'^\d{2}:\d{2}$')
                : RegExp(r'^\w{3}, \w{3} \d+$'),
          ),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
