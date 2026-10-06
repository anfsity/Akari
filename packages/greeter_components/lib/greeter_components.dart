/// Optional reusable visual components for compiled Akari themes.
///
/// [StandardGreeterComponents] implements the component identifiers used by the
/// fallback theme. A theme opts into this factory explicitly; scene and SDK
/// packages do not require it or prescribe its component identifiers.
library;

export 'components/greeter_components.dart' show StandardGreeterComponents;
export 'components/account_components.dart' show AccountPortrait;
export 'components/authentication_components.dart' show CredentialField;
