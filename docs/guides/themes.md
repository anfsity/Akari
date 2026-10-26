---
title: Develop a theme
description: Turn the fallback example into an independent theme package.
---

Akari themes are independent Dart/Flutter packages. You can start by copying the static `fallback` theme and customizing its scene layout, visual tokens, and components.

## 1. Scaffold from the fallback theme

Copy `themes/fallback` into a new package directory from the repository root:

```sh
cp -R themes/fallback themes/ocean
```

Update the copied files to give your theme a unique identity:

| File | Required changes |
| --- | --- |
| `pubspec.yaml` | Set `name: theme_ocean` (keep the existing SDK path dependencies). |
| `lib/ocean.scene.json` | Rename from `lib/fallback.scene.json` and set `"id": "ocean"`. |
| `lib/theme.dart` | Import `ocean.scene.g.dart`, rename the builder to `buildOceanTheme`, pass `oceanSceneDocument`, and set `id: 'ocean'`. |
| `lib/fallback.scene.g.dart` | Delete the copied generated file—the CLI generates `ocean.scene.g.dart` on build. |

:::note
The builder function name derives from the `pubspec.yaml` package name (`theme_ocean` -> `buildOceanTheme`), not the directory name. A theme may import `greeter_components`, but must never import another concrete theme package. See the [Theme package contract](../reference/theme-package.md).
:::

## 2. Run and iterate

Launch your new theme in a desktop window with hot reload enabled (using the `akari` launcher or `fvm dart run tool/akari.dart`):

```sh
AKARI_WINDOW_MODE=windowed akari run --theme themes/ocean
```

- **Edit layout & visibility**: Modify `lib/ocean.scene.json`. On save, the CLI regenerates `ocean.scene.g.dart` and reloads the scene. If generation fails, the running window keeps the last valid scene until you fix the JSON.
- **Edit styling & widgets**: Modify `lib/theme.dart` to adjust `ThemeTokens`, background/motion renderers, or the component factory. See the [Scene format reference](../reference/scene-format.md) for JSON schema rules.

## 3. Bundle theme assets

1. Place images under `assets/` in your theme directory and declare them in `pubspec.yaml`:

   ```yaml
   flutter:
     uses-material-design: true
     assets:
       - assets/wallpaper.jpg
   ```

2. Reference bundled assets in your scene JSON using the `packages/<package_name>/` prefix:

   ```json
   {
     "kind": "image",
     "asset": "packages/theme_ocean/assets/wallpaper.jpg",
     "color": "#0d151a",
     "scrimOpacity": 0.35,
     "blurSigma": 0
   }
   ```

Ensure your `ThemeBundle` in `lib/theme.dart` registers an `image` background renderer (included by default in the fallback template).

## 4. Maintain an external theme repository

A theme package can live outside the Akari repository:

1. Point all SDK path dependencies (`theme_sdk`, `scene`, `greeter_components`, and `scene_codegen` in `dev_dependencies`) to your local Akari checkout.
2. Pass the external directory path to `--theme`:

   ```sh
   akari preview --theme /path/to/ocean
   akari build --theme /path/to/ocean
   ```

:::tip
Production builds compile the selected theme's Dart code and assets directly into the greeter executable. Runtime loading of arbitrary Dart code is not part of the theme contract.
:::

## Next steps

- [Develop theme components](components.md)
- [Develop and test](testing.md)
