import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

class _CredentialHost implements GreeterHost {
  @override
  final ValueNotifier<AuthPromptSlots> authPromptSlots = ValueNotifier((
    mode: AuthMode.prompting,
    selectedUser: null,
    prompt: (kind: PromptKind.secret, text: 'Password'),
    error: null,
    promptError: null,
  ));
  @override
  final credentialController = TextEditingController(text: 'retained');
  @override
  final credentialFocusNode = FocusNode();

  void dispose() {
    authPromptSlots.dispose();
    credentialController.dispose();
    credentialFocusNode.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected host access: ${invocation.memberName}');
}

void main() {
  test('all declared palette, material and motion combinations round-trip', () {
    final original = buildDefaultTheme();
    expect(original.document.themeProperties, isEmpty);
    expect(original.presetCatalog.properties.map((property) => property.name), [
      'palette',
      'material',
      'motion',
    ]);
    for (final palette in ['wallpaper', 'ocean', 'rose', 'violet']) {
      for (final material in ['airy', 'frosted', 'solid']) {
        for (final motion in ['terrace', 'gentle', 'none']) {
          final document = original.document.copyWith(
            themeProperties: {
              'palette': palette,
              'material': material,
              'motion': motion,
              'private': 'keep',
            },
          );
          final reopened = decodeSceneDocument(encodeSceneDocument(document));
          final theme = buildDefaultTheme(document: reopened);
          expect(theme.document.themeProperties, document.themeProperties);
          expect(theme.tokens.disableAnimations, motion == 'none');
          expect(theme.tokens.mediumMotion == Duration.zero, motion == 'none');
          expect(theme.bundle.motions.isEmpty, motion == 'none');
          expect(
            theme.materialTheme.inputDecorationTheme.enabledBorder,
            material == 'airy'
                ? isA<UnderlineInputBorder>()
                : isA<OutlineInputBorder>(),
          );
          expect(theme.document.nodes.length, original.document.nodes.length);
        }
      }
    }
  });

  test(
    'explicit palettes remain stable while wallpaper palette follows the seed',
    () {
      final original = buildDefaultTheme();
      Color accent(String palette, Color seed) => buildDefaultTheme(
        seed: seed,
        document: original.document.copyWith(
          themeProperties: {'palette': palette},
        ),
      ).materialTheme.colorScheme.primary;
      expect(
        accent('wallpaper', Colors.red),
        isNot(accent('wallpaper', Colors.blue)),
      );
      for (final palette in ['ocean', 'rose', 'violet']) {
        expect(accent(palette, Colors.red), accent(palette, Colors.blue));
      }
      expect(accent('ocean', Colors.red), isNot(accent('rose', Colors.red)));
      expect(accent('rose', Colors.red), isNot(accent('violet', Colors.red)));
    },
  );

  test(
    'unsupported global preset values are rejected by the runtime builder',
    () {
      final original = buildDefaultTheme();
      for (final key in ['palette', 'material', 'motion']) {
        expect(
          () => buildDefaultTheme(
            document: original.document.copyWith(
              themeProperties: {key: 'unsupported'},
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'credential materials render real surfaces and retain host input',
    (tester) async {
      final host = _CredentialHost();
      addTearDown(host.dispose);
      final original = buildDefaultTheme();
      final node = original.document.nodes.firstWhere(
        (node) => node.componentId == 'credentialField',
      );
      for (final material in ['airy', 'frosted', 'solid']) {
        final theme = buildDefaultTheme(
          document: original.document.copyWith(
            themeProperties: {'material': material},
          ),
        );
        final components = theme.components(
          GreeterThemeContext(
            host: host,
            tokens: theme.tokens,
            canvas: theme.document.canvas,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.materialTheme,
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 100,
                child: Builder(
                  builder: (context) => components.build(context, node),
                ),
              ),
            ),
          ),
        );
        expect(find.byType(TextField), findsOneWidget);
        expect(
          find.byType(BackdropFilter),
          material == 'frosted' ? findsOneWidget : findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(host.credentialController),
        );
        expect(host.credentialController.text, 'retained');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
