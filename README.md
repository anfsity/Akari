# Akari

_A themeable Linux greeter built with Flutter and Rust._

**Akari** means **A**uthentication **K**it for **A**rtistic, **R**esponsive
**I**nterfaces.

Build a login screen with custom Flutter components, backgrounds, layouts, and
animations. The Rust backend handles authentication through greetd and PAM,
keeping theme development focused on presentation.

Named after Akari Hankui (半杭朱理) from _Asobi no Kankei_, a character I love.

[Documentation](https://anfsity.github.io/Akari/) ·
[Quick start](docs/getting-started/quick-start.md) ·
[Code map](docs/architecture/code-map.md)

## Features

- **Custom themes.** Compose Flutter widgets with the Theme SDK, using typed
  login state and actions. Each theme owns its components, visual tokens, and assets.
- **Scenes and animation.** Describe layout, visibility, backgrounds, and motion
  in scene JSON. The selected theme and generated scene code are compiled into
  the executable.
- **Theme Studio.** Edit scenes visually with a canvas, layer list, property
  inspector, and undo/redo, using the selected theme's components and assets.
- **Multiple displays.** Show the greeter across connected monitors and adapt
  layouts to different resolutions and display scales.

## Quick start

Development requires Linux, FVM, Rust/Cargo, the Flutter Linux build dependencies,
and D-Bus tools. Follow the
[environment setup guide](docs/getting-started/installation.md) for prerequisites,
then run:

```sh
git clone https://github.com/anfsity/Akari.git
cd Akari
bash scripts/bootstrap-toolchain.sh
fvm dart run tool/akari.dart preview --theme themes/fallback
```

Preview opens a resizable desktop window with simulated login state. Dart,
asset, and scene changes reload on save in debug mode.

`themes/fallback` is a small, static starting point for a new theme. Use
`--theme themes/default` to try the default theme, or follow the
[theme development guide](docs/guides/themes.md) to create your own.

## Development

Run these commands from the repository root:

| Task | Command |
| --- | --- |
| Run with the mock backend | `fvm dart run tool/akari.dart run --theme themes/fallback` |
| Open Theme Studio | `fvm dart run tool/akari.dart run studio --theme themes/fallback` |
| Build a production bundle | `fvm dart run tool/akari.dart build --theme themes/fallback` |
| Run repository checks | `fvm dart run tool/akari.dart verify` |

The mock backend runs on a private D-Bus session and accepts `password` for the
simulated login. Preview and Studio use simulated frontend state without a backend.

A production build outputs the Flutter bundle at `build/out/fallback` and the
Rust backend at `build/out/backend`. Keep the full Flutter bundle together when
distributing it. For real login testing, follow the
[greetd testing guide](docs/guides/greetd-testing.md).

See the [CLI reference](docs/reference/cli.md) for options, nested Sway sessions,
and the optional `akari` shell launcher.

## Documentation

The [documentation site](https://anfsity.github.io/Akari/) covers setup, theme
development, and the implementation. Useful starting points:

| Topic | Guide |
| --- | --- |
| Create a theme | [Theme development](docs/guides/themes.md) |
| Build custom widgets | [Component development](docs/guides/components.md) |
| Edit scenes visually | [Theme Studio](docs/internal/theme-studio.md) |
| Check resolution and scaling | [Display testing](docs/guides/display-testing.md) |
| Understand the implementation | [Architecture](docs/architecture/overview.md) · [Code map](docs/architecture/code-map.md) |

## License

[Apache License 2.0](LICENSE).
