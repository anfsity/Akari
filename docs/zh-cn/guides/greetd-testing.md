---
title: 独立 greetd 测试
description: 构建和安装真实登录测试工具、捕获显示器信息、查看日志并恢复 SDDM。
---

测试工具位于 `scripts/greetd-test/`，安装到 `/opt/akari-test`。它使用正式版后端，通过 greetd 验证登录，并调用 logind 处理电源操作。这里的挂起、重启和关机都会实际执行。系统启动时仍由 SDDM 管理登录；桌面开发用的 `akari run` 默认模拟登录和电源操作。

请按照[开发工具](../reference/cli.md)中的说明安装绑定当前仓库的 `akari` 启动器。`akari greetd-test --help` 会列出全部操作；每项操作还有自己的帮助信息及 bash/zsh 补全。安装、启动和恢复在需要时会请求 sudo；状态查询和常规日志读取不需要提升权限。

先确认没有上一次测试或恢复计时器在运行，再构建并安装：

```sh
akari greetd-test install
```

安装命令会先以 Linux release 模式构建默认主题和正式版后端，使用四个并行任务。若从 sudo 命令运行，使用 sudo 的调用者构建；若直接以 root 运行，则使用仓库所有者构建，以便 SDK 和仓库缓存仍归该用户所有。SDK 选择遵循相同的仓库配置和 CLI 覆盖项 `AKARI_FLUTTER_BIN` / `AKARI_DART_BIN`。构建失败时会在修改任何已安装文件或备份前中止。

构建成功后，安装器会将旧前端、后端、脚本和配置备份到 `/opt/akari-test/backups/` 下。它不会切换显示管理器。安装器要求现有测试环境中包含 `greeter` 账户和可写目录 `/opt/akari-test/state`。

安装期间还会将当前 Sway 或 Hyprland 桌面的显示器顺序保存到 `/opt/akari-test/display-layout.json`。支持对齐成水平行或垂直列。此功能使用桌面配置的排列方式；显示器硬件无法报告自己在另一块屏幕的物理哪一侧。登录时，工具会根据 Sway 报告的逻辑尺寸依次排列屏幕，并保留登录环境的显示模式和缩放。热插拔会重新计算位置；新发现的输出会排在已保存输出之后，直到重新安装工具并捕获新的排列。如果当前桌面排列无法捕获，安装器会保留之前的布局；若从未保存过布局，则使用 Sway 的自动排列。调整屏幕排列后，请从桌面重新安装工具。

保存工作、退出桌面，然后在 tty3 登录并运行：

```sh
akari greetd-test start
```

启动前会通过 `SUDO_TTY` 检查你所在的终端，即使 sudo 创建了 PTY 也能正确识别。它会拒绝仍有图形用户会话运行的情况（忽略正在关闭的会话）、检查 SDDM 启动配置，并在修改服务前记录诊断信息。停止 SDDM 前会先启用恢复机制。设置失败时会立即恢复；测试服务退出时由 systemd 的 `ExecStopPost` 恢复；服务运行期间另有一个独立的十分钟计时器兜底。登录成功后，登录界面会退出，greetd 继续管理用户桌面会话。

要手动恢复，请切换到 tty3 并运行：

```sh
akari greetd-test restore
```

恢复脚本可以单独运行，不依赖 CLI。systemd 计时器和退出回调始终直接调用 `/opt/akari-test/restore.sh`。即使仓库或 Flutter/Dart SDK 不可用，也可在 tty3 运行以下命令恢复：

```sh
sudo /opt/akari-test/restore.sh
```

CLI、计时器和退出回调共用这一套恢复实现。`install`、`start` 和 `restore` 接受 `--dry-run`，只打印将要执行的命令，不会请求 sudo 或修改文件。真正执行 `start` 时仍会运行前置检查。CLI 不会更改 TTY 或活动桌面要求。

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

检查最近一次启动尝试，或恢复流程使用的测试：

```sh
akari greetd-test logs
akari greetd-test logs --run current --file backend -n 100
akari greetd-test logs --run current --file flutter --follow
```

`logs` 默认选择调用者最近的启动尝试及其 `start.log`。即使测试已恢复，`--run current` 仍会选中上次启用恢复的测试。`--file` 接受 `start`、`backend`、`flutter`、`sway`、`lifecycle`、`restore` 和 `journal`。登录界面日志会选择最新会话；旧会话文件仍保留在已保存的运行路径下。`--lines`（`-n`）默认为 100；`--follow`（`-f`）会跟踪所选文件，包括稍后才创建的文件，但不会自动切换会话。

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
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
