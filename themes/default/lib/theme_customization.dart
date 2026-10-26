import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

enum TerraceLabelVariant { regular, large }

enum TerracePalette { wallpaper, ocean, rose, violet }

enum TerraceMaterial { airy, frosted, solid }

enum TerraceMotion { terrace, gentle, none }

const terracePalette = ThemeChoiceProperty(
  name: 'palette',
  label: 'Palette',
  defaultValue: TerracePalette.wallpaper,
  choices: {
    TerracePalette.wallpaper: 'From wallpaper',
    TerracePalette.ocean: 'Ocean',
    TerracePalette.rose: 'Rose',
    TerracePalette.violet: 'Violet',
  },
);

const terraceMaterial = ThemeChoiceProperty(
  name: 'material',
  label: 'Control material',
  defaultValue: TerraceMaterial.airy,
  choices: {
    TerraceMaterial.airy: 'Airy underline',
    TerraceMaterial.frosted: 'Frosted capsule',
    TerraceMaterial.solid: 'Solid surface',
  },
);

const terraceMotion = ThemeChoiceProperty(
  name: 'motion',
  label: 'Motion',
  defaultValue: TerraceMotion.terrace,
  choices: {
    TerraceMotion.terrace: 'Terrace entrance',
    TerraceMotion.gentle: 'Quiet fade',
    TerraceMotion.none: 'No animations',
  },
);

const terracePresetCatalog = ThemePresetCatalog(
  properties: [terracePalette, terraceMaterial, terraceMotion],
);

const terraceLabelText = ThemeTextProperty(
  name: 'text',
  label: 'Text',
  defaultValue: 'Welcome',
);

const terraceLabelVariant = ThemeChoiceProperty(
  name: 'variant',
  label: 'Text style',
  defaultValue: TerraceLabelVariant.regular,
  choices: {
    TerraceLabelVariant.regular: 'Regular',
    TerraceLabelVariant.large: 'Large',
  },
);

const terraceComponentCatalog = ThemeComponentCatalog(
  components: {
    'terraceLabel': ThemeComponentDefinition(
      label: 'Heading and caption',
      properties: [terraceLabelText, terraceLabelVariant],
    ),
    'dateTime': dateTimeComponent,
  },
);
