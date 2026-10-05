# Akari

_A themeable Linux greeter built with Flutter and Rust._

**Akari** means **A**uthentication **K**it for **A**rtistic, **R**esponsive
**I**nterfaces. Its Rust backend connects to greetd/PAM for authentication;
the Theme SDK, scene tools, and Theme Studio support theme development; and
themes use components, backgrounds, layouts, and animation to express their
style while adapting to different display sizes and scales.

Named after Akari Hankui (半杭朱理) from _Asobi no Kankei_, a character I love.
[KADOKAWA's official introduction](https://group.kadokawa.co.jp/information/promotional_topics/article-14487.html)
uses the name 半杭朱理.

[Documentation](https://anfsity.github.io/Akari/) ·
[Quick start](docs/getting-started/quick-start.md) ·
[Code map](docs/architecture/code-map.md)

## Development

Prepare the Linux dependencies and FVM described in the
[environment guide](docs/getting-started/installation.md), then run:

```sh
bash scripts/bootstrap-toolchain.sh
fvm dart run tool/akari.dart preview --theme themes/fallback
```

Use `run` for the private D-Bus/mock-backend workflow, `build` for a production
bundle, and `verify` for repository checks. See the
[CLI reference](docs/reference/cli.md) for commands and diagnostics.

The [documentation maintenance guide](docs/guides/documentation.md) covers the
Astro Starlight site, generated API reference, and GitHub Pages publishing.
