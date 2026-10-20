---
title: CLI 与开发工具
description: 查命令、选项、显示配置和运行报告。
---

<a id="commands-and-targets"></a>

## 命令与目标

在仓库根目录执行 `fvm dart run tool/akari.dart COMMAND`；安装[命令行启动器](#shell-launcher-and-completion)后，可直接运行 `akari COMMAND`。

| 命令 | 用途 | 命令专属选项 |
| --- | --- | --- |
| `build` | 构建所选主题、正式版后端与原生启动画面 | `--theme`（`-t`）、`--jobs`（`-j`）、`--mode`（`-m`）、`--platform` |
| `preview` | 在单窗口中自动演示登录 UI 流程并退出 | `--theme`、`--jobs`、`--scenario` |
| `run` | 在私有 D-Bus 会话中启动登录界面与后端 | `--theme`、`--jobs`、`--mode`、`--backend` |
| `run sway` | 在嵌套或无头 Sway 中运行登录界面 | `run` 选项 + `--display-profile`、`--resolution`、`--scale`、`--sway-backend` |
| `run splash` | 单独预览原生启动加载动画，直至手动关闭 | `--jobs`、`--mode`、`--light` |
| `run studio` | 使用已编译主题可视化编辑场景 | `--theme`、`--jobs` |
| `verify` | 检查共享代码、Rust 后端、Studio 与主题项目 | `--theme` |
| `generate-scenes` | 从场景 JSON 生成类型化 Dart（`*.scene.g.dart`） | `--theme` |
| `verify-perf`（`perf`） | 运行主题声明的性能门槛检查 | `--theme`、`--` 后的透传参数 |
| `trace-perf`（`trace`） | 运行主题声明的性能耗时跟踪 | `--theme`、`--` 后的透传参数 |
| `install` | 构建并部署正式开机登录环境 | `--theme`、`--jobs`、`--keyring`、`--dry-run` |
| `install cli` | 安装绑定当前仓库的 `akari` 启动器与补全脚本 | `--shell`、`--prefix`、`--rc` |
| `uninstall` | 卸载正式（`login`）、测试（`test`）或全部（`all`）环境 | `--scope`、`--dry-run` |
| `login enable` / `disable` | 启用 Akari 开机登录或恢复原显示管理器 | `--dry-run` |
| `login rollback` | 在 `current` 与 `previous` 已部署版本间回滚切换 | `--dry-run` |
| `login configure-keyring` | 无需重新构建即可配置 greetd 密钥环 PAM 规则 | `--keyring`、`--dry-run` |
| `login enable-gaze` / `disable-gaze` | 在标准 Arch greetd 上启用 Gaze 人脸认证或恢复密码栈 | `--dry-run` |
| `login status` | 查看部署状态与 systemd 服务状态 | `--format` |
| `login logs` | 查看服务 journal 或最新登录界面会话日志 | `--component`、`--lines`（`-n`）、`--follow`（`-f`） |
| `toolchain check` / `setup` | 检查或初始化开发环境依赖 | `--dry-run` |
| `docs build-api` / `verify` | 构建 Dart API 文档或校验已构建的文档站点 | `--dry-run`；`verify` 在 `--` 后传入站点目录 |
| `script list` / `run` | 查看并调用仓库 `scripts/` 下的辅助脚本 | `list --format`、`run SCRIPT --dry-run -- 参数` |
| `completion` | 输出 Shell 补全脚本 | `--shell` |
| `greetd-test` | 管理独立 TTY 真实登录测试 | 详见[独立 greetd 测试](../guides/greetd-testing.md) |

### 通用选项与约定

- **报告与演练选项**：`build`、`preview`、`run*`、`verify`、`generate-scenes` 与 `*-perf` 均支持 `--format text|json`、`--report PATH` 和 `--dry-run`。
- **短选项**：`-t`（`--theme`）、`-m`（`--mode`）、`-j`（`--jobs`）。同一次调用中同一参数请勿混用长短选项。
- **透传参数**：`perf`、`trace`、`script run` 和 `docs verify` 会将 `--` 之后的参数原样转发给底层命令。
- **Theme Studio 说明**：`akari run studio` 固定使用 debug 模式且不启动后端（不接受 `--mode` 或 `--backend`）。操作说明见仓库内的 [Theme Studio 文档](https://github.com/anfsity/Akari/blob/main/docs/zh-cn/internal/theme-studio.md)。

<a id="production-login-installation"></a>

## 安装正式登录环境

在已安装 `systemd`、`/usr/bin/greetd`、`/usr/bin/sway`、`python3`、`swaymsg`、`swaybg`、`dbus-daemon`、`busctl`、`setpriv` 和 `accountsservice` 的 Linux 主机上，以普通用户部署开机登录环境：

```sh
akari install --theme themes/default --jobs 4
akari login enable
akari login status
```

### 部署目录与资源结构

| 路径 / 资源 | 说明 |
| --- | --- |
| `akari-greeter` | 运行登录界面的专用无特权系统账户 |
| `/opt/akari/releases/` | 按版本存放的发布程序包，通过 `current` 和 `previous` 符号链接切换 |
| `/etc/akari/greetd.toml` 与 `sway.conf` | Akari 专用配置文件（不修改系统原有的 `/etc/greetd/config.toml`） |
| `/etc/akari/display-layout.json` | 首次安装时从当前 Sway/Hyprland 桌面捕获的显示器排列顺序 |
| `/var/lib/akari/greeter/` | 持久化的登录账户与桌面会话偏好 |
| `/var/log/akari/greeter/session-*/` | 每次启动生成的 `backend.log`、`flutter.log` 与 `sway.log`（无需 `sudo` 即可读取） |

### 密钥环（Keyring）与 PAM 配置

`akari install` 会自动配置 `/etc/pam.d/greetd`（首次修改前备份至 `/var/lib/akari/greetd.pam.before-keyring`）：

- `--keyring auto`（默认）：自动检测已安装的 `pam_gnome_keyring.so` 与 `pam_kwallet5.so`（若均未安装，在 Arch、Debian/Ubuntu、Fedora 终端下会提示是否安装）。
- `--keyring gnome` / `--keyring kwallet`：仅配置指定提供方（GNOME Keyring 使用 `use_authtok` + `auto_start`；KWallet 使用 `auto_start force_run`）。
- `--keyring none`：仅移除 Akari 管理的密钥环配置块，保留其他 PAM 规则。
- 无需重新构建即可单独更新已有安装的密钥环 PAM 规则：
  ```sh
  akari login configure-keyring --keyring gnome
  ```
- 在 Arch Linux 上启用或移除 Gaze 人脸认证：使用 `akari login enable-gaze` 与 `akari login disable-gaze`（详见 [Gaze 接入指南](../guides/greetd-testing.md#在-arch-上接入-greetd)）。

### 服务管理、日志与卸载

```sh
# 查看服务 journal 或组件日志（backend、flutter、sway）
akari login logs
akari login logs --component backend --lines 200
akari login logs --component flutter --follow

# 回滚到上一版本或恢复原开机显示管理器
akari login rollback
akari login disable

# 卸载环境（--scope login | test | all）
akari uninstall --scope all --dry-run
akari uninstall
```

:::tip[TTY 紧急恢复]
`login enable` 和 `login disable` 只更新开机服务符号链接，不会中断当前桌面。如果在 TTY 下无法访问源码仓库或 Dart SDK，可直接调用已安装的控制器恢复原显示管理器：
```sh
sudo python3 /opt/akari/manage.py disable
```
随后重启系统即可回到原来的登录管理器。
:::

<a id="shell-launcher-and-completion"></a>

## Shell 启动器与补全

在用户目录安装绑定当前仓库的 `akari` 启动器（`~/.local/bin/akari`）与补全脚本（`~/.local/share/akari/`）：

```sh
fvm dart run tool/akari.dart install cli --shell zsh
# 或使用 bash：
fvm dart run tool/akari.dart install cli --shell bash
```

- 可通过 `--prefix PATH` 和 `--rc PATH` 自定义安装路径与 Shell 配置文件。
- 若移动了仓库位置，或修改了 `tool/src/cli/definition.dart` 中的命令定义，请重新执行 `install cli`。
- 使用 `akari completion --shell zsh|bash` 可直接输出补全脚本内容。

## 仓库脚本

在仓库根目录下查找并运行 `scripts/` 中的辅助脚本：

```sh
akari script list
akari script list --format json
akari script run run-backend.sh -- --help
akari script run greetd-test/display-layout.py -- capture
```

## 构建、预览和运行

- **`build`**：解析主题依赖、生成场景代码、在 `build/tool/hosts/` 下准备可复用宿主，并编译 release 前端包与正式版 Rust 后端。
- **`run`**：在私有 D-Bus 会话中启动登录界面与 Rust 模拟后端（`--backend real` 切换正式通信）。支持保存后热重载；默认全屏（`AKARI_WINDOW_MODE=windowed` 切换窗口模式）。
- **`preview`**：在无边框单窗口中依次自动演示 `face-success` 与 `password-fallback`（可通过 `--scenario NAME` 单选），完成后自动退出。
- **`run splash`**：打开独立窗口预览原生启动加载动画，按 `Escape` 或关闭窗口退出。

<a id="sway-sessions-and-display-profiles"></a>

## Sway 会话与显示配置

在嵌套或无头 Sway 合成器中复现独立登录界面的显示比例：

```sh
akari run sway
akari run sway --display-profile reference
akari run sway --display-profile login
akari run sway --resolution 1920x1080 --scale 1.6
akari run sway --display-profile reference --sway-backend headless
```

### 显示配置模式（`--display-profile`）

| 模式 | 行为说明 |
| --- | --- |
| `auto`（默认） | 自动从 `/opt/akari-test/current-run/greeter/session-*/` 导入最新的 DRM 登录快照至 `${XDG_STATE_HOME:-~/.local/state}/akari/display-profiles/login.json`；若无快照则回退到 `reference`。 |
| `login` | 强制使用已导入或新捕获的真实 TTY 登录快照；若不存在有效快照则直接报错。 |
| `reference` | 固定使用 `config/sway/reference.json`（`1920x1080`，缩放 `1.0`）。在多屏环境下使用 `--resolution` 或 `--scale` 单输出覆盖时必须指定此模式。 |

### 输出校验与 Hyprland 缩放补偿

- **运行产物**：保存在 `build/tool/runs/<run-id>/sway/` 下，包含 `display-report.json`、`outputs.json`、`sway.log`、`flutter.log` 以及 `screenshots/` 下的首帧输出截图。
- **Hyprland 缩放补偿**：在 Hyprland 下，`run sway` 会读取窗口所在显示器的缩放并自动应用 `内层缩放 = 目标登录缩放 / Hyprland 显示器缩放`。在同一显示器上全屏时，逻辑视口与独立 TTY Sway 完全一致。
- **无头模式校验**：`--sway-backend headless` 强制校验输出尺寸与缩放，若实际输出与目标存在偏差则判定运行失败。

详细对比步骤请参阅[显示器与缩放测试](../guides/display-testing.md)。

## 验证与生成宿主

`akari verify` 会检查共享包、Rust 后端、Theme Studio 以及 `themes/` 下的全部主题（或通过 `--theme PATH` 指定单个主题）。

如需在 IDE 中直接调试根项目入口，可使用默认注入 `themes/default` 的 `tool/dev_main.dart`：

```sh
fvm dart run tool/akari.dart generate-scenes --theme themes/default
fvm flutter run -d linux --target tool/dev_main.dart
```

## 报告与构建输出

- **运行报告**：每次 CLI 运行都会在 `build/tool/runs/<run-id>/` 下生成 `report.json`（Schema v1）、`events.jsonl` 及各步骤的 `stdout`/`stderr` 日志。可通过 `--format json` 输出到标准输出，或用 `--report PATH` 写入指定文件。
- **执行演练（Dry Run）**：`--dry-run` 以 JSON 格式打印计划的步骤图与产物路径，不执行实际构建或创建运行目录。
- **构建产物符号链接**：Linux 构建成功后，会在 `build/out/<theme-name>` 和 `build/out/backend` 创建指向构建缓存的相对符号链接。

## 主题性能命令

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default -- --cycles 5
fvm dart run tool/akari.dart trace-perf --theme themes/default
```

`verify-perf`（`perf`）与 `trace-perf`（`trace`）会执行所选主题在 `pubspec.yaml` 的 `perf:` 块中声明的命令，并校验 `AKARI_PERF_OUTPUT_DIR`（`build/tool/runs/<run-id>/perf/`）下的 `result.json`。详见[主题性能约定](theme-package.md#performance-protocol)。

## 构建缓存和并行执行

- **宿主缓存复用**：`build/tool/hosts/` 下的生成宿主会保留 Flutter 与 CMake 缓存，并在解析依赖后传入 `--no-pub` 加速后续运行。
- **并行任务数（`--jobs COUNT`）**：在并行编译 Rust 后端与 Flutter 前端时，通过 CMake Ninja pool 限制 Cargo 与原生 C++ 编译/链接并发数。
- **构建目录隔离**：模拟后端与正式后端分别使用 `backend/target/akari-mock/` 和 `backend/target/akari-real/`，同一主题通过进程锁串行执行，不同主题可并行构建。
