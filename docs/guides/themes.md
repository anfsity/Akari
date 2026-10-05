---
title: Develop a theme
description: Turn the fallback example into an independent theme package.
---

## Start from the small example

The fallback project is a useful starting point because it has a fixed palette
and no continuous motion. From the repository root:

```sh
cp -R themes/fallback themes/ocean
```

Update the copied project:

1. Set the package name in `pubspec.yaml` to `theme_ocean`.
2. Rename `lib/fallback.scene.json` to `lib/ocean.scene.json` and set its `id` to `ocean`.
3. In `lib/theme.dart`, import `ocean.scene.g.dart`, rename the exported builder
   to `buildOceanTheme`, use `oceanSceneDocument`, and set the theme definition's
   `id` to `ocean`.
4. Remove any copied `fallback.scene.g.dart`; the build generates the new source.

Keep the copied SDK path dependencies when the project is in `themes/ocean`.
Its optional shared widgets come from `greeter_components`; it does not import
the fallback theme itself. The package name determines the builder name, not
the folder name. See the [theme package contract](../reference/theme-package.md).

## Preview and iterate

```sh
fvm dart run tool/mozais.dart preview --theme themes/ocean
```

Edit the scene JSON to change layout and visibility. Edit `theme.dart` to change
tokens, renderer registrations, and the component factory. Use the
[scene format reference](../reference/scene-format.md) for field rules.

The CLI regenerates scene Dart before running the host. Do not hand-edit generated
files. A failed generation retains the running scene; fix the JSON and save again.

## Add assets

Put project-owned images under `assets/` and declare them in the theme's
`pubspec.yaml`. Flutter package paths include the package name:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/wallpaper.jpg
```

```json
{
  "kind": "image",
  "asset": "packages/theme_ocean/assets/wallpaper.jpg",
  "color": "#0d151a",
  "scrimOpacity": 0.35,
  "blurSigma": 0
}
```

This object replaces the document's `background` object. The theme's visual
bundle must register an image renderer, as the fallback example does.

## Keep an external project

A theme can live outside the repository. Point each SDK path dependency at its
corresponding package in your Mozais checkout, including the `scene_codegen`
development dependency. Asset paths must use the external theme's package name.

```sh
fvm dart run tool/mozais.dart preview --theme /path/to/ocean
fvm dart run tool/mozais.dart build --theme /path/to/ocean
```

The CLI builds a host for this selected project. Installing new Dart or Flutter
theme code at runtime is outside the theme contract: production themes are
compiled into the executable.

Continue with [component development](components.md) and [testing](testing.md).
