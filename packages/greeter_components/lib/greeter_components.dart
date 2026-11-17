/// Optional reusable visual components for compiled Akari themes.
///
/// [StandardGreeterComponents] implements the component identifiers used by the
/// fallback theme. A theme opts into this factory explicitly; scene and SDK
/// packages do not require it or prescribe its component identifiers.
library;

export 'src/components/account_components.dart' show AccountPortrait;
export 'src/components/authentication_components.dart'
    show CredentialField, PrimaryAction;
export 'src/components/greeter_components.dart' show StandardGreeterComponents;
export 'src/components/system_components.dart'
    show
        ClockVariant,
        MinuteClockBuilder,
        PowerActions,
        clockVariant,
        dateTimeComponent,
        getFormattedClockTime;
