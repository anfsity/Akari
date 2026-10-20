---
title: 开发主题
description: 从简单示例出发，制作自己的 Flutter 登录主题。
---

Akari 主题是独立的 Dart/Flutter 包。最快的起步方式是复制静态无动画的 `fallback` 主题，在此基础上修改场景布局、样式参数（Tokens）与组件实现。

## 1. 基于示例创建新主题

在仓库根目录复制 `themes/fallback`：

```sh
cp -R themes/fallback themes/ocean
```

按以下清单修改复制后的项目标识：

| 文件 | 修改项 |
| --- | --- |
| `pubspec.yaml` | 将包名设为 `name: theme_ocean`（保留原有的 SDK 路径依赖）。 |
| `lib/ocean.scene.json` | 由 `lib/fallback.scene.json` 重命名而来，并将 `"id"` 改为 `"ocean"`。 |
| `lib/theme.dart` | 导入 `ocean.scene.g.dart`，将导出函数改名为 `buildOceanTheme`，传入 `oceanSceneDocument`，并将主题定义的 `id` 设为 `'ocean'`。 |
| `lib/fallback.scene.g.dart` | 删除复制过来的生成文件，CLI 构建时会自动生成 `ocean.scene.g.dart`。 |

:::note
导出函数名由 `pubspec.yaml` 中的包名决定（如 `theme_ocean` 对应 `buildOceanTheme`），与文件夹名称无关。主题可以复用 `greeter_components`，但不得直接依赖另一个具体主题包。详见[主题包约定](../reference/theme-package.md)。
:::

## 2. 实时预览与迭代

以窗口模式启动主题并开启热重载：

```sh
AKARI_WINDOW_MODE=windowed fvm dart run tool/akari.dart run --theme themes/ocean
```

- **调整布局与显示条件**：编辑 `lib/ocean.scene.json`。保存时 CLI 会自动重新生成 Dart 代码并热重载。如果 JSON 格式有误，窗口会保留上一次有效画面，修正并再次保存即可恢复。
- **调整样式与组件**：在 `lib/theme.dart` 中修改 `ThemeTokens`、背景渲染器、动效注册表及组件工厂。JSON 字段说明请参阅[场景格式](../reference/scene-format.md)。

## 3. 添加图片与资源

1. 将图片放入主题目录的 `assets/` 下，并在 `pubspec.yaml` 中声明：

   ```yaml
   flutter:
     uses-material-design: true
     assets:
       - assets/wallpaper.jpg
   ```

2. 在场景 JSON 中使用 `packages/<包名>/` 路径引用该资源（替换 `background` 字段）：

   ```json
   {
     "kind": "image",
     "asset": "packages/theme_ocean/assets/wallpaper.jpg",
     "color": "#0d151a",
     "scrimOpacity": 0.35,
     "blurSigma": 0
   }
   ```

同时确保 `lib/theme.dart` 的 `ThemeBundle` 中已注册 `image` 背景渲染器（fallback 模板已默认注册）。

## 4. 在仓库外独立维护主题

主题项目也可以存放在 Akari 仓库之外：

1. 将 `pubspec.yaml` 中的 SDK 路径依赖（包括 `dev_dependencies` 中的 `scene_codegen`）指向本地 Akari 仓库对应目录。
2. 通过 `--theme` 传入外部目录路径：

   ```sh
   fvm dart run tool/akari.dart preview --theme /path/to/ocean
   fvm dart run tool/akari.dart build --theme /path/to/ocean
   ```

:::tip
正式构建会将所选主题的 Dart 代码与资源直接编译进可执行文件，不支持在运行时动态加载未编译的 Dart 代码。
:::

## 下一步

- [开发主题组件](components.md)
- [开发与测试](testing.md)
