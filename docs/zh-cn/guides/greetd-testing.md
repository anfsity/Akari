---
title: 独立 greetd 测试
description: 构建和安装真实登录测试工具、捕获显示器信息、查看日志并恢复 SDDM。
---

测试工具位于 `scripts/greetd-test/`，安装到 `/opt/akari-test`。它使用正式版后端，通过 greetd 验证登录，并调用 logind 处理电源操作。这里的挂起、重启和关机都会实际执行。系统启动时仍由 SDDM 管理登录；桌面开发用的 `akari run` 默认模拟登录和电源操作。

## 用户会话环境

正式版和测试工具的 greetd 配置均启用 profile 加载。greetd 先读取 `/etc/profile` 和 `~/.profile`，随后 Akari 将认证用户的命令转发给 `$SHELL`，以非交互 login 模式启动。默认 shell 自行读取原生配置，Akari 不选择配置文件，也不按 shell 名称分支。原生 shell 集成测试覆盖 bash、sh、zsh 和 fish。

桌面需要的环境变量应导出到登录配置，例如 zsh 的 `.zprofile`，或 fish 配置中 `status is-interactive` 条件之外的部分；`.zshrc` 不会加载。原生 shell 的启动文件可能再次读取 POSIX profile，因此 profile 中的操作应支持重复执行。安装时会保留已有配置；升级旧安装时，请移除 `/etc/akari/greetd.toml` 中的 `source_profile = false`，或改为 `true`。重新安装测试工具会同时更新配置和后端。

用户侧执行器完整保留命令参数，仅在 LANG 缺失或为空时补入 `LANG=C.UTF-8`；它记录 locale 检查结果，保留用户明确设置的覆盖值。桌面的 stdout/stderr 和启动信息写入 `${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/` 下的私有 `session-*.log`。进入原生 login shell 前，Akari 会将 shell 的 stdout/stderr 写入同一目录下的私有 `startup-*.log`，目录按原生 shell 启动前的环境解析。如果 shell 修改了 `XDG_STATE_HOME`，桌面日志使用新目录，启动日志仍留在原目录。greetd 自己加载 profile 和执行 PAM 的输出早于这个启动器，不受此重定向控制。登录界面启动和退出时的诊断写入各自的 `lifecycle.log`。

原生启动画面在 Sway 启动前和用户桌面启动前运行，通过 libseat 管理真实 VT 上的 DRM/KMS 访问。启动器等待绘制进程退出、释放控制权后才启动后续合成器；图形不可用时继续正常登录。默认使用暗色背景，从首次呈现起最短展示 3 秒，在登录启动器环境中设置 `AKARI_SPLASH_DURATION` 可同时调整两次展示。退出前清理终端文本和回滚缓冲。用 `akari preview` 预览同一绘制器。生命周期与实机验收项目见[交接实现](https://github.com/anfsity/Akari/blob/main/docs/proposals/login-handoff.md)；黑屏间隔、VT 切换、桌面启动失败和退出登录仍需真实 VT 验证。

仓库提供的 Sway 配置会在 Flutter 加载期间将启动画面的静态截图用作背景，需要安装 `swaybg`。已有正式安装保留原配置；将 `/etc/akari/sway.conf` 的背景行改为 `output * bg "$AKARI_LOG_DIR/splash.png" fit #15191f` 即可启用这个等待画面。

桌面与 systemd 服务的就绪时序由所选桌面或会话管理器负责。选择 UWSM 管理的会话时，环境同步和退出清理由 UWSM 处理。直接启动 compositor 时保留现有集成；新增 custom 回调无法约束上游已经启动的应用。验证时应分别检查 compositor 子进程、新启动的用户服务和新激活的 D-Bus 服务。greetd 交接成功不代表桌面已经就绪。

## 人脸认证

登录界面唤醒且账号、会话已选定时，Akari 会自动开始系统认证。识别期间会持续显示 PAM 提供的提示；认证成功后直接启动所选桌面，无需提交密码。若识别超时或摄像头不可用后 PAM 继续请求密码，输入框会在同一次认证中恢复，并自动获得键盘焦点。

初步使用 [Gaze](https://github.com/GunduLabs/gaze) 作为人脸认证提供方。其默认顺序 PAM 模式会先识别人脸，失败后继续现有密码规则。Akari 直接展示 PAM 提示，不根据文案猜测认证提供方，因此翻译后的消息也能正常显示。摄像头设置、人脸录入、超时和回退策略由提供方与 PAM 管理；Akari 不采集摄像头画面、不存储人脸模型。预览和模拟模式不会执行真实人脸识别。

### 安装并验证 Gaze

按照 Gaze 的[安装指南](https://gaze.gundulabs.com/guide/installation.html)操作。Arch 上的人脸认证包名是 `gaze-bin`；AUR 中名为 `gaze` 的另一个包是文件监视工具。基础包已经包含守护进程、CLI 和 PAM 模块，Akari 无需桌面扩展。

Arch 包的安装钩子还会配置 sudo 和 polkit。若第一轮只接入 greetd，应在安装前创建 `/etc/gaze/pam-sudo.optout`，备份现有 polkit 规则并记录 `/etc/pam.d/polkit-1` 是否存在，安装完成后恢复 polkit 规则；升级时也要重新检查这些钩子。参见 Gaze 的 [PAM 指南](https://gaze.gundulabs.com/guide/pam.html)。

```sh
sudo install -d -m 0755 /etc/gaze
sudo touch /etc/gaze/pam-sudo.optout
yay -S --needed gaze-bin
sudo systemctl enable --now gazed
gaze config
```

先使用 CPU 推理、`security.level = "medium"` 并保持活体检测开启。先选 RGB 摄像头，确认红外采集及补光正常后再添加 IR。多摄像头时优先使用 `usb:VVVV:PPPP` 标识，避免 `/dev/video*` 编号变化选错设备。Gaze 直接采集硬件，登录界面的识别不依赖用户的 PipeWire 会话。参见[配置指南](https://gaze.gundulabs.com/guide/configuration.html)。

在桌面中以实际登录账号执行录入和验证：

```sh
gaze add-face default
gaze auth --verbose
gaze doctor
```

需要管理员权限的命令会请求认证。`gaze auth` 验证摄像头和识别，不测试 greetd 的 PAM 规则；先确认这里能够成功识别，再接入 PAM。修改 PAM 前备份原规则，并保留已认证的管理员终端。

### 在 Arch 上接入 greetd

对于 `/etc/pam.d/greetd` 引用 `system-local-login` 的标准 Arch 规则，先创建 `/etc/pam.d/akari-gaze`：

```text
#%PAM-1.0
auth       requisite                    pam_shells.so
auth       requisite                    pam_faillock.so preauth
auth       [success=ignore default=3]    pam_gaze.so
auth       requisite                    pam_env.so
auth       requisite                    pam_faillock.so authsucc
auth       sufficient                   pam_permit.so
auth       include                      system-local-login
```

再将 `/etc/pam.d/greetd` 开头的 `auth` 规则替换为：

```text
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       substack     akari-gaze
```

保留已有 `account`、`session` 和密钥环规则。辅助规则先检查 Shell 与失败锁定；人脸成功后加载环境、清除此前的认证失败记录，并只完成子栈。Gaze 失败或模块不可用时跳过这三条人脸成功规则，继续原密码栈。密码失败会结束子栈，不会清除失败记录。父栈随后仍执行密钥环认证规则；若直接在父栈使用 `sufficient`，这些规则会被跳过。

父栈必须使用 `substack`：`include` 会将规则展开到父栈，其中成功的 `sufficient` 也会结束父栈认证。辅助规则中的数字跳转覆盖三条普通模块规则，不跳过 include；后续修改时需要检查。若主机的 PAM 布局不同，应按发行版规则和 Gaze 的 [greetd 指南](https://gaze.gundulabs.com/guide/greetd.html)调整，不要直接复制上述配置。

初步配置保持 TPM 密码存储关闭。人脸登录不会自动解锁有密码的密钥环；进入桌面后按提示解锁即可。Gaze 的可选密钥环集成属于独立配置，额外存储和 PAM 要求见其 greetd 指南。

### 验证真实登录

安装当前 Akari 构建后，使用下文的独立测试工具。验证人脸成功且无需提交密码、识别失败后密码登录、摄像头不可用时密码回退，以及识别中切换账号后旧尝试无法启动会话。已锁定的账号即使人脸匹配也必须保持拒绝。失败时查看后端日志及 `journalctl -u gazed -b`。恢复备份的 greetd 规则并删除 `/etc/pam.d/akari-gaze` 即可移除本次试用接入。

## 安装和运行测试工具

请按照[开发工具](../reference/cli.md)中的说明安装绑定当前仓库的 `akari` 启动器。`akari greetd-test --help` 会列出全部操作；每项操作还有自己的帮助信息及 bash/zsh 补全。安装、启动和恢复在需要时会请求 sudo；状态查询和常规日志读取不需要提升权限。

先确认没有上一次测试或恢复计时器在运行，再构建并安装：

```sh
akari greetd-test install
akari greetd-test install --theme themes/preset1
```

通过 `--theme PATH`（或 `-t PATH`）选择主题项目，默认使用当前仓库的 `themes/default`。相对路径以命令调用目录为准，也支持仓库外的主题项目。`start` 使用已安装的主题；切换主题时重新运行 `install` 并指定所需项目。

安装命令会先以 Linux release 模式构建所选主题和正式版后端，使用四个并行任务。若从 sudo 命令运行，使用 sudo 的调用者构建；若直接以 root 运行，则使用仓库所有者构建，以便 SDK 和仓库缓存仍归该用户所有。SDK 选择遵循相同的仓库配置和 CLI 覆盖项 `AKARI_FLUTTER_BIN` / `AKARI_DART_BIN`。构建失败时会在修改任何已安装文件或备份前中止。

构建成功后，安装器会将旧前端、后端、脚本和配置备份到 `/opt/akari-test/backups/` 下。它不会切换显示管理器。安装器要求现有测试环境中包含 `greeter` 账户和可写目录 `/opt/akari-test/state`。

安装期间还会将当前 Sway 或 Hyprland 桌面的显示器顺序保存到 `/opt/akari-test/display-layout.json`。支持对齐成水平行或垂直列。此功能使用桌面配置的排列方式；显示器硬件无法报告自己在另一块屏幕的物理哪一侧。登录时，工具会根据 Sway 报告的逻辑尺寸依次排列屏幕，并保留登录环境的显示模式和缩放。热插拔会重新计算位置；新发现的输出会排在已保存输出之后，直到重新安装工具并捕获新的排列。如果当前桌面排列无法捕获，安装器会保留之前的布局；若从未保存过布局，则使用 Sway 的自动排列。调整屏幕排列后，请从桌面重新安装工具。

保存工作、退出桌面，然后在 tty3 登录并运行：

```sh
akari greetd-test start
```

启动前会检查 SDDM 启动配置，并在修改服务前记录诊断信息；不会检测调用者终端或登录会话。停止 SDDM 前会先启用恢复机制。设置失败时会立即恢复；测试服务退出时由 systemd 的 `ExecStopPost` 恢复；服务运行期间另有一个独立的十分钟计时器兜底。登录成功后，登录界面会退出，greetd 继续管理用户桌面会话。

要手动恢复，请切换到 tty3 并运行：

```sh
akari greetd-test restore
```

恢复脚本可以单独运行，不依赖 CLI。systemd 计时器和退出回调始终直接调用 `/opt/akari-test/restore.sh`。即使仓库或 Flutter/Dart SDK 不可用，也可在 tty3 运行以下命令恢复：

```sh
sudo /opt/akari-test/restore.sh
```

CLI、计时器和退出回调共用这一套恢复实现。`install`、`start` 和 `restore` 接受 `--dry-run`，只打印将要执行的命令，不会请求 sudo 或修改文件。真正执行 `start` 时仍会运行前置检查。

使用以下命令检查已安装资源、SDDM、测试服务、恢复计时器和日志路径：

```sh
akari greetd-test status
akari greetd-test status --format json
```

日志保存在 `/opt` 之外的 `/var/tmp/akari-greetd-test-<caller-uid>/`。UID 为 1000 的用户使用 `/var/tmp/akari-greetd-test-1000/`。所有用户都可以直接读取启动、前端、后端、合成器和恢复日志，包括测试运行期间，无需 sudo 或特殊组权限。直接以 root 调用时使用 UID 0，同样保留读取权限。日志目录权限为 `0755`，日志文件为 `0644`；只有所有者和 root 可以写入。

每次进入日志初始化阶段的启动尝试都会创建独立的 `<timestamp>-<pid>/start.log`。运行前置检查之前会打印日志目录。`latest` 符号链接指向最新尝试（包括前置检查失败的尝试）；`current` 指向最近一次已启用恢复的测试。安装文件还会保留指向该目录的 `current-run` 指针，供启动和恢复使用，因此后续被拒绝的尝试不会改写恢复日志位置。restore 也会打印测试日志目录。

每次登录界面启动都会将 `backend.log`、`flutter.log`、`sway.log`、`lifecycle.log` 和 `outputs.json` 保存在自己的 `greeter/session-*/` 目录中；返回桌面不会覆盖此前的日志。恢复过程中会保存测试和 SDDM journal，以及恢复操作自己的时间戳和结果。

初始输出排列完成后，启动还会发布 `display-profile.json`，其中包含规范化后的活动输出、DRM 登录来源、运行/会话路径、捕获时间及原始 `outputs.json` 校验和。此文件记录启动状态；热插拔会继续调整输出排列，但不会更新该快照。若显示器组合发生变化，请重新运行测试以捕获新配置。未保存排列的会话使用 Sway 初始位置，并执行相同的快照捕获流程。

回到桌面后，`akari run sway` 会把最新的有效显示配置快照导入本地状态目录。快照必须带有来源标记。它会忽略不完整、损坏或没有标记的捕获结果，并保留已有的有效本地配置。`--display-profile reference` 使用项目的 1920×1080、缩放 1 参考配置（无头模式下为固定分辨率）；`--display-profile login` 则要求存在有效登录截图。更多覆盖项、多输出映射、实际输出检查和内层截图说明见[开发工具](../reference/cli.md)。请重新安装测试工具以启用带来源标记的捕获流程；登录进程不会写入开发者的 home 目录。

接下来可以按[显示测试](display-testing.md#compare-a-nested-session-with-standalone-login)的步骤，在桌面上复现登录时的显示配置，或生成固定分辨率截图。

<a id="capture-the-actual-tty-login-screen"></a>

## 截取真实 TTY 登录画面

重新运行 `akari greetd-test install` 安装当前截图脚本，并确保系统已安装
`grim`。在实际登录画面上按 `Print`，会为每块活动屏幕保存一张 PNG；
按 `Shift+Print` 会延迟 3 秒，便于展开账户或 session 菜单后截图。
快捷键由登录会话的 Sway 处理，不会唤醒休眠界面或关闭菜单。

截图保存在当前运行的 `greeter/session-*/screenshots/<timestamp>-*/` 下。
每次截图创建新目录，恢复 SDDM 后仍保留，可直接从桌面读取，无需 sudo。
UID 1000、默认日志位置下，可用以下命令查看：

```sh
ls /var/tmp/akari-greetd-test-1000/current/greeter/session-*/screenshots/
akari greetd-test logs --run current --file screenshot
```

每个目录包含 `output-1.png` 等图像和 `capture.json`；后者记录图像对应的
显示器、当时的实际模式、逻辑尺寸和缩放。每块屏幕独立使用自身缩放截图，
避免混合 DPI 时被 grim 的默认最高缩放放大。截图时不会修改启动时的
`display-profile.json`，因此热插拔后的捕获也有自己独立的显示参数。

调整样式时以这些真实画面为参照。回到 Hyprland 后，使用
`akari run sway --theme themes/default --display-profile login`，在同一块
显示器上将嵌套窗口全屏再对比；普通预览窗口的逻辑视口可能不同。

检查最近一次启动尝试，或恢复流程使用的测试：

```sh
akari greetd-test logs
akari greetd-test logs --run current --file backend -n 100
akari greetd-test logs --run current --file flutter --follow
```

`logs` 默认选择调用者最近的启动尝试及其 `start.log`。即使测试已恢复，`--run current` 仍会选中上次启用恢复的测试。`--file` 接受 `start`、`backend`、`flutter`、`sway`、`lifecycle`、`screenshot`、`restore` 和 `journal`。登录界面日志会选择最新会话；旧会话文件仍保留在已保存的运行路径下。`--lines`（`-n`）默认为 100；`--follow`（`-f`）会跟踪所选文件，包括稍后才创建的文件，但不会自动切换会话。

启动测试时可设置自定义日志位置（相对路径以命令调用目录为准）：

```sh
akari greetd-test start --log-dir /var/tmp/my-akari-test
```

登录用户必须能够遍历自定义目录的所有父目录；启动会在停止 SDDM 前检查访问权限。`logs` 会从保存的配置发现该路径，无需再次提供 `--log-dir`。通常无法访问权限为私有的 home 目录，请改用 `/var/tmp` 下的路径。安装工具还会为每位调用者保留 `latest-run-<uid>` 指针，包括前置检查失败的尝试。恢复时会自动解析已保存的 `current-run` 指针，无需再次指定自定义路径。每次准备测试时，会将缩放和日志根目录写入 `config.json`。旧设置 `AKARI_TEST_SCALE` 和 `AKARI_TEST_LOG_DIR` 已由这些显式启动选项取代。

要查看 systemd 服务实时输出，可运行 `sudo journalctl -u akari-test.service -f`；测试恢复时会将可直接读取的 `journal.log` 保存下来。重新安装脚本后，`/opt/akari-test` 才会包含这些更新。旧版 `/opt/akari-test/test-runs/` 中的日志仍会保留。

独立登录测试默认使用缩放 1，可以用来对比桌面预览的效果。可通过 `akari greetd-test start --scale NUMBER` 明确覆盖；Sway 会将实际输出模式和缩放记录到 `outputs.json`。`akari run sway` 会补偿外层 Hyprland 显示器缩放，因此同一显示器和模式下的全屏嵌套窗口，在逻辑视口和内容大小上会与 TTY 一致。内层缩放等于所选登录缩放除以 Hyprland 显示器缩放；显示器设置不会被修改。无头测试会复现所选配置的固定分辨率和缩放。

无需 root 或修改活动系统，即可验证测试工具的控制流程：

```sh
python3 test/support/greetd_test_workflow_test.py
python3 test/support/greetd_screenshot_test.py
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
