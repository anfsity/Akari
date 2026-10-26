import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

enum TerraceLabelVariant { regular, large }

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
