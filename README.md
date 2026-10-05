# Mozais

A Linux greeter with compile-time Flutter themes and a Rust bridge to greetd/PAM.
Themes own presentation; the backend owns authentication and system operations.

[Documentation](https://anfsity.github.io/Mozais/) ·
[Quick start](docs/getting-started/quick-start.md) ·
[Code map](docs/architecture/code-map.md)

## Development

Prepare the Linux dependencies and FVM described in the
[environment guide](docs/getting-started/installation.md), then run:

```sh
bash scripts/bootstrap-toolchain.sh
fvm dart run tool/mozais.dart preview --theme themes/fallback
```

Use `run` for the private D-Bus/mock-backend workflow, `build` for a production
bundle, and `verify` for repository checks. See the
[CLI reference](docs/reference/cli.md) for commands and diagnostics.

The [documentation maintenance guide](docs/guides/documentation.md) covers the
Astro Starlight site, generated API reference, and GitHub Pages publishing.
