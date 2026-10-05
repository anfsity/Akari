---
title: 开发主题
description: 从简单示例出发，制作自己的 Flutter 登录主题。
---

## 复制一个主题作为起点

fallback 主题使用固定配色，没有持续动画，结构比较简单。可以先复制它，再逐步改成自己的设计。在仓库根目录运行：

```sh
cp -R themes/fallback themes/ocean
```

更新复制后的项目：

1. 在 `pubspec.yaml` 中将包名称改为 `theme_ocean`。
2. 将 `lib/fallback.scene.json` 重命名为 `lib/ocean.scene.json`，并将其中的 `id` 设为 `ocean`。
3. 在 `lib/theme.dart` 中导入 `ocean.scene.g.dart`，将导出的 builder 重命名为 `buildOceanTheme`，使用 `oceanSceneDocument`，并将主题定义的 `id` 设为 `ocean`。
4. 删除复制来的 `fallback.scene.g.dart`；构建时会生成新的源文件。

如果主题放在 `themes/ocean`，复制来的 SDK 路径依赖可以保留。需要通用组件时，可以使用 `greeter_components`。不要直接依赖 fallback 主题。builder 名称由包名决定，目录名可以不同；具体规则见[主题包约定](../reference/theme-package.md)。

## 边改边看效果

```sh
fvm dart run tool/akari.dart preview --theme themes/ocean
```

布局和显示条件在场景 JSON 中修改；配色、字体等样式参数、背景渲染器和组件工厂在 `theme.dart` 中修改。场景字段的含义见[场景格式](../reference/scene-format.md)。

工具会自动把场景 JSON 生成为 Dart 代码，生成文件无需手动编辑。如果 JSON 有误，预览会继续显示上一次成功生成的场景；修正后保存即可重试。

## 添加资源

把主题使用的图片放进 `assets/`，再在 `pubspec.yaml` 中声明：

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

把场景文档中的 `background` 替换为上面的对象。主题还需要注册图片背景渲染器，写法可以参考 fallback 示例。

## 在仓库外维护项目

主题也可以单独放在仓库之外。把 SDK 的路径依赖指向 Akari 仓库中对应的包，开发依赖 `scene_codegen` 也要一起调整。图片等资源的路径要使用你自己的主题包名。

```sh
fvm dart run tool/akari.dart preview --theme /path/to/ocean
fvm dart run tool/akari.dart build --theme /path/to/ocean
```

CLI 会为指定主题生成应用项目并构建。正式版本会把主题代码编译进应用，因此修改或更换主题代码后需要重新构建。

接下来可阅读[组件开发](components.md)和[测试指南](testing.md)。
