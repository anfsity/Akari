import 'package:shadcn_flutter/shadcn_flutter.dart';

enum StudioPalette {
  zinc('Zinc'),
  neutral('Neutral'),
  slate('Slate'),
  stone('Stone'),
  blue('Blue'),
  rose('Rose'),
  violet('Violet');

  const StudioPalette(this.label);

  final String label;

  ColorScheme getColorScheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = switch (this) {
      zinc => dark ? ColorSchemes.darkZinc : ColorSchemes.lightZinc,
      neutral => dark ? ColorSchemes.darkNeutral : ColorSchemes.lightNeutral,
      slate => dark ? ColorSchemes.darkSlate : ColorSchemes.lightSlate,
      stone => dark ? ColorSchemes.darkStone : ColorSchemes.lightStone,
      blue =>
        dark ? LegacyColorSchemes.darkBlue() : LegacyColorSchemes.lightBlue(),
      rose =>
        dark ? LegacyColorSchemes.darkRose() : LegacyColorSchemes.lightRose(),
      violet =>
        dark
            ? LegacyColorSchemes.darkViolet()
            : LegacyColorSchemes.lightViolet(),
    };
    if (!dark) return scheme;
    // Lift near-black shadcn surfaces toward their own secondary tone while
    // preserving each preset's foreground, accent and border contrast.
    return scheme.copyWith(
      background: () => Color.lerp(scheme.background, scheme.secondary, 0.4)!,
      card: () => Color.lerp(scheme.card, scheme.secondary, 0.55)!,
      popover: () => Color.lerp(scheme.popover, scheme.secondary, 0.55)!,
    );
  }
}
