---
title: 独立 greetd 测试
description: 构建与安装真实登录测试工具、捕获显示器布局、查看会话日志并安全恢复系统。
---

独立测试工具位于 `scripts/greetd-test/`，安装到 `/opt/akari-test`。它使用正式版后端连接真实的 `greetd` 与 `systemd-logind`，同时保留系统原有的开机显示管理器配置，并提供自动恢复兜底机制。

:::caution
测试工具连接真实系统后端，因此挂起、重启和关机操作会实际执行。日常桌面开发请使用 `akari run`（默认使用模拟认证与模拟电源）。
:::

<a id="user-session-environment"></a>

## 用户会话环境

### Shell 与 Profile 初始化流程

正式环境与测试工具的 greetd 配置均默认启用 `source_profile`：

1. `greetd` 先加载 `/etc/profile` 和 `~/.profile`。
2. Akari 将已认证用户的会话命令以非交互 login 模式转发给 `$SHELL`（支持 `bash`、`sh`、`zsh` 和 `fish`）。
3. 用户的登录 Shell 自行加载原生登录配置（如 `.zprofile` 或 `status is-interactive` 之外的 fish 配置；不会加载交互式的 `.zshrc`）。
4. 用户侧执行器保留完整 `argv`，仅在 `LANG` 为空时补充 `LANG=C.UTF-8`，随后启动所选桌面。

:::note[升级旧版配置]
安装过程会保留已有的 `/etc/akari/greetd.toml`。升级旧版本时，请移除其中的 `source_profile = false`（或将其设为 `true`）。重新安装测试工具会一并更新其配置与后端。
:::

### 会话与启动日志

| 日志文件 | 所在路径 | 记录内容 |
| --- | --- | --- |
| `startup-*.log` | `${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/` | 进入原生 login shell 到启动桌面之前的 stdout/stderr |
| `session-*.log` | `${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/` | 桌面进程的 stdout/stderr 与启动诊断信息 |
| `lifecycle.log` | 登录界面（greeter）会话日志目录 | 登录界面启动与退出阶段的生命周期诊断 |

### 原生 DRM/KMS 启动画面

在真实 VT 上，`akari-splash` 会在 Sway 启动前以及用户桌面启动前，通过 `libseat` 与 DRM/KMS 绘制纯黑背景（`#000000`）的原生加载画面：

- **最短展示时长**：从首帧呈现起默认保持 3 秒。在启动器环境中设置 `AKARI_SPLASH_DURATION` 可同时调整两段过渡时长（设为 `0` 则取消保持）。
- **Sway 背景平滑衔接**：Flutter 初始化期间，Sway 配置通过 `swaybg` 显示启动画面保存的静态快照（`output * bg "$AKARI_LOG_DIR/splash.png" fit #000000`）。
- **终端清理**：释放 VT 前会自动清空终端文本与回滚缓冲。实机验收项请参阅[原生登录交接提案](https://github.com/anfsity/Akari/blob/main/docs/zh-cn/proposals/login-handoff.md)。

<a id="facial-authentication"></a>

## 人脸认证

### 架构分离与职责边界

Akari 自身**不实现也不负责任何生物特征识别算法、传感器硬件驱动或人脸模型管理**。

在系统架构上，Akari 仅仅是通过 `greetd` 接入 Linux 标准的 **PAM（Pluggable Authentication Modules）** 机制：

- **职责彻底分离**：生物识别的所有细节（如打开摄像头、活体检测、特征比对）均由专有的 PAM 模块和外部守护进程在特权层级独立完成。
- **展示层隔离**：Akari 的前端与后端均运行在非特权沙箱中，既不采集任何硬件数据，也不接触用户的生物特征信息。

### 工作原理

1. **状态透明透传**：当唤醒登录界面并选定账户后，Akari 触发系统 PAM 流程。在 PAM 模块执行比对期间，若发出任何状态消息，Akari 会通过 D-Bus 实时捕获并直观展示在界面上。
2. **免密直接登入**：若生物认证成功，PAM 向上返回成功信号，Akari 立即调用桌面合成器启动用户会话，无需输入密码。
3. **同会话无缝回退**：若比对超时或识别未命中，PAM 栈会自动转向下一条认证规则（通常是密码验证）。Akari 在同一次认证尝试（保持相同的 `attempt_id`）中无缝将焦点恢复到密码输入框，交互无需重新开始。

### 参考实现：Gaze

在 Akari 的开发与验收体系中，我们选用 [Gaze](https://github.com/GunduLabs/gaze) 作为**官方验证的参考实现（Reference Implementation）**。

为了免去在 Arch Linux 等环境上手动配置危险 PAM 文件的繁琐步骤，Akari CLI 提供了外挂式管理命令（`akari login enable-gaze` 与 `akari login disable-gaze`），用于安全、可逆地将 Gaze 子栈编排至 `/etc/pam.d/greetd`。

### 安装并验证 Gaze

1. 在 Arch Linux 上安装 `gaze-bin`（注意不要安装同名的文件监听工具 `gaze`），若仅在 `greetd` 中试用，可提前创建 opt-out 文件跳过 `sudo` PAM 钩子：

   ```sh
   sudo install -d -m 0755 /etc/gaze
   sudo touch /etc/gaze/pam-sudo.optout
   yay -S --needed gaze-bin
   sudo systemctl enable --now gazed
   gaze config
   ```

   :::tip[推荐初始配置]
   建议先使用 CPU 推理、`security.level = "medium"` 并开启活体检测，优先配置 RGB 摄像头（多摄像头时推荐使用 `usb:VVVV:PPPP` 标识，避免 `/dev/video*` 编号漂移）。详见 Gaze 的[安装指南](https://gaze.gundulabs.com/guide/installation.html)与[配置指南](https://gaze.gundulabs.com/guide/configuration.html)。
   :::

2. 在接入 PAM 前，先在桌面中使用实际登录账户录入人脸并测试识别：

   ```sh
   gaze add-face default
   gaze auth --verbose
   gaze doctor
   ```

<a id="connect-greetd-on-arch"></a>

### 在 Arch 上接入 greetd

确认 `gaze auth` 识别成功后，为标准 Arch `greetd` PAM 栈启用 Gaze：

```sh
akari login enable-gaze --dry-run
akari login enable-gaze
```

`enable-gaze` 执行的操作：
- 将 `/etc/pam.d/greetd` 备份至 `/var/lib/akari/greetd.pam.before-gaze`。
- 生成 `/etc/pam.d/akari-gaze`，并将 `auth include system-local-login` 替换为 `auth substack akari-gaze`。
- 使用 PAM 子栈（substack）隔离人脸 `sufficient` 规则，确保人脸通过后仍会继续执行父栈的密钥环（keyring）钩子；人脸失败或不可用时则自动回退至原有密码栈。

:::note[人脸登录与密钥环解锁]
默认未启用 TPM 密码存储时，人脸登录不会向密钥环提供密码口令，进入桌面后按提示手动解锁即可。若启用了 Gaze 的可选密钥环集成，请再运行 `akari login configure-keyring --keyring gnome` 为 GNOME 钩子补上 `use_authtok`。
:::

如需移除 Gaze PAM 接入并恢复纯密码登录：

```sh
akari login disable-gaze
```

### 验证真实登录

使用下方的独立测试工具验证以下场景：
1. 人脸识别通过后无需输入密码即可直接进入桌面。
2. 识别失败或遮挡摄像头后可平滑回退至密码输入。
3. 识别过程中切换账户会取消上一次认证尝试。
4. 被失败锁定的账户即使人脸匹配也依然拒绝登录。

## 安装和运行测试工具

### 1. 构建并安装

确认当前没有正在运行的测试或恢复计时器，然后执行安装：

```sh
# 安装默认主题
akari greetd-test install

# 或指定其他主题项目
akari greetd-test install --theme themes/fallback
```

`install` 会以 release 模式（4 并行任务）构建主题与正式版后端，将旧文件备份到 `/opt/akari-test/backups/`，并将当前 Sway 或 Hyprland 桌面的显示器排列顺序保存到 `/opt/akari-test/display-layout.json`。

### 2. 从 TTY 启动测试

1. 保存工作并退出当前桌面会话。
2. 切换到 `tty3` 登录，启动测试：

   ```sh
   akari greetd-test start
   ```

   常用可选参数：
   - `--scale NUMBER`：覆盖登录界面的输出缩放（默认为 `1`）。
   - `--log-dir /var/tmp/my-akari-test`：指定自定义的全局可遍历日志根目录。
   - `--dry-run`：仅输出执行计划，不停止现有显示管理器。

`start` 会在停止当前显示管理器前挂载多重恢复保护。遇到以下任一情况时都会自动恢复原有显示管理器：
- 前置检查或启动阶段失败；
- `akari-test.service` 退出（通过 `ExecStopPost` 触发）；
- 服务运行满 10 分钟（触发独立兜底计时器）。

### 3. 手动恢复原有显示管理器

如需在 `tty3` 手动结束测试并恢复原显示管理器：

```sh
akari greetd-test restore

# 若仓库或 SDK 不可用，可直接调用独立恢复脚本：
sudo /opt/akari-test/restore.sh
```

### 4. 查看状态与日志

无需 `sudo` 即可查看服务状态、恢复计时器与日志路径：

```sh
akari greetd-test status
akari greetd-test status --format json
```

日志默认保存在 `/var/tmp/akari-greetd-test-<caller-uid>/`（例如 UID 1000 对应 `/var/tmp/akari-greetd-test-1000/`），所有用户均可直接读取：

- `latest`：指向最近一次启动尝试（含前置检查失败）。
- `current`：指向最近一次已启用恢复保护的测试运行。
- `current/greeter/session-*/`：存放每次登录界面会话的 `backend.log`、`flutter.log`、`sway.log`、`lifecycle.log`、`outputs.json` 与 `display-profile.json`。

通过 CLI 直接查阅日志：

```sh
# 查看最近一次尝试的 start.log
akari greetd-test logs

# 查看当前测试中 backend.log 的最后 100 行
akari greetd-test logs --run current --file backend -n 100

# 实时跟踪 flutter.log
akari greetd-test logs --run current --file flutter --follow
```

`--file` 支持的值：`start`、`backend`、`flutter`、`sway`、`lifecycle`、`screenshot`、`restore` 和 `journal`。

<a id="capture-the-actual-tty-login-screen"></a>

## 截取真实 TTY 登录画面

系统安装 `grim` 后，可在真实登录界面上直接按键为每块活动屏幕保存截图，且不会唤醒休眠界面或关闭已展开的菜单：

| 快捷键 | 行为 |
| --- | --- |
| `Print` | 立即为每台活动显示器保存一张 PNG 截图 |
| `Shift+Print` | 延迟 3 秒后截图（方便先展开账户或会话菜单） |

截图与 `capture.json` 元数据保存在 `greeter/session-*/screenshots/<timestamp>-*/` 下，返回原桌面后仍可直接读取：

```sh
akari greetd-test logs --run current --file screenshot
```

回到桌面后，`akari run sway` 会自动导入最近一次有效测试生成的 `display-profile.json`，方便你[对比嵌套会话与独立登录](display-testing.md#compare-a-nested-session-with-standalone-login)。

## 离线工作流自检

无需 root 权限或停止显示管理器，即可运行以下测试校验脚本控制流：

```sh
python3 test/support/greetd_test_workflow_test.py
python3 test/support/greetd_screenshot_test.py
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
