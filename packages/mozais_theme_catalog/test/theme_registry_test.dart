import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_theme_catalog/mozais_theme_catalog.dart';

void main() {
  test('builds the default palette from its extracted seed', () {
    final warm = ThemeRegistry.resolve(
      ThemeRegistry.defaultThemeName,
      seed: const Color(0xffe53935),
    );
    final cool = ThemeRegistry.resolve(
      ThemeRegistry.defaultThemeName,
      seed: const Color(0xff1e88e5),
    );

    expect(
      warm.materialTheme.colorScheme.primary,
      isNot(cool.materialTheme.colorScheme.primary),
    );
    expect(
      warm.materialTheme.colorScheme.surfaceContainerHigh,
      isNot(cool.materialTheme.colorScheme.surfaceContainerHigh),
    );
  });
}
