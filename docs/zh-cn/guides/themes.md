---
title: 开发主题
description: 将 fallback 示例改造为可独立使用的主题包。
---

## 从精简示例开始

fallback 项目使用固定配色且没有持续动效，适合作为起点。在仓库根目录运行：

```sh
cp -R themes/fallback themes/ocean
```

更新复制后的项目：

1. 在 `pubspec.yaml` 中将包名称改为 `theme_ocean`。
2. 将 `lib/fallback.scene.json` 重命名为 `lib/ocean.scene.json`，并将其中的 `id` 设为 `ocean`。
3. 在 `lib/theme.dart` 中导入 `ocean.scene.g.dart`，将导出的 builder 重命名为 `buildOceanTheme`，使用 `oceanSceneDocument`，并将主题定义的 `id` 设为 `ocean`。
4. 删除复制来的 `fallback.scene.g.dart`；构建时会生成新的源文件。

当项目位于 `themes/ocean` 时，保留复制来的 SDK path dependency。可选共享 widget 来自 `greeter_components`；不要导入 fallback 主题本身。builder 名称取决于包名，与目录名无关。请参阅[主题包约定](../reference/theme-package.md)。

## 预览并迭代

```sh
fvm dart run tool/akari.dart preview --theme themes/ocean
```

编辑场景 JSON 可修改布局和可见性；编辑 `theme.dart` 可修改 token、渲染器注册和组件工厂。字段规则见[场景格式参考](../reference/scene-format.md)。

CLI 会在运行宿主前重新生成场景 Dart 代码。不要手动编辑生成文件。生成失败时，会继续保留正在运行的场景；修复 JSON 后再保存。

## 添加资源

将项目自有图片放入 `assets/`，并在主题的 `pubspec.yaml` 中声明：

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

此对象会替换文档中的 `background` 对象。主题的视觉 bundle 必须注册 image renderer，具体可参照 fallback 示例。

## 在仓库外维护项目

主题可以放在仓库之外。将每个 SDK path dependency 指向 Akari checkout 中对应的 package，包括 `scene_codegen` 开发依赖。资源路径必须使用外部主题的包名。

```sh
fvm dart run tool/akari.dart preview --theme /path/to/ocean
fvm dart run tool/akari.dart build --theme /path/to/ocean
```

CLI 会为所选项目构建宿主。主题约定不支持运行时安装新的 Dart 或 Flutter 代码：生产主题会编译进可执行文件。

接下来可阅读[组件开发](components.md)和[测试指南](testing.md)。
