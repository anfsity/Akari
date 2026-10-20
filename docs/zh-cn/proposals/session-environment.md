# 用户会话环境约定

> [!NOTE]
> **状态**：原生 login shell 转发、`argv` 参数保真、Locale 诊断与用户会话日志已实现。PAM/VT 真实登录与桌面服务就绪时序仍需实机验证。

## 1. 背景与设计目标

通过 Akari 启动的桌面环境必须完整继承用户的登录环境变量，同时由 `systemd --user` 或 D-Bus 激活的用户级服务也必须在启动前拿到对应的显示与会话变量。

## 2. 启动顺序与职责划分

```text
greetd / PAM
  -> greetd 加载 POSIX profile（/etc/profile、~/.profile）
  -> 用户 login shell（$SHELL -l -c）初始化原生登录配置
  -> Akari 用户侧执行器保留 argv、检查 locale 并打开用户日志
  -> 所选桌面入口启动桌面或会话管理器
  -> 会话管理器发布激活环境（activation environment）并确认就绪
  -> 依赖该环境的用户服务启动（并在桌面退出时清理）
```

| 阶段 | 负责方 | 完成条件 |
| --- | --- | --- |
| **身份验证与 PAM** | `greetd` + PAM | 建立已认证的用户上下文 |
| **POSIX 登录基线** | `greetd`（`source_profile = true`） | 以目标用户身份加载 `/etc/profile` 与 `~/.profile` |
| **原生 Shell 登录配置** | 用户的 `$SHELL` | 加载原生登录文件（如 `.zprofile`、非交互 fish 配置），不执行交互式 `.zshrc` |
| **桌面命令交接与诊断** | Akari 用户侧执行器（`session_launch.rs`） | 清理内部 `AKARI_*` 变量，在 `LANG` 缺失时补充 `LANG=C.UTF-8`，并以完整 `argv` 直接 `exec` 桌面命令 |
| **激活环境发布与服务编排** | 桌面 / 会话管理器（如 UWSM、GNOME、Plasma 或合成器钩子） | 在依赖服务启动前将显示与桌面变量发布至 `systemd --user` / D-Bus |

> [!IMPORTANT]
> `greetd` 的 `start_session` 成功回复仅代表登录界面已完成交接，不代表桌面合成器或用户级 systemd 服务已经就绪。

## 3. Shell 转发与 Locale 规则

- **不依赖特定 Shell 名称的统一转发**：Akari 以非交互 login 模式调用 `$SHELL`（`-l -c 'exec "$VARIABLE"'`），不针对特定 Shell 硬编码配置文件路径（集成测试已覆盖 `bash`、`sh`、`zsh` 和 `fish`）。
- **支持重复加载的 POSIX Profile**：原生 login shell 启动时可能会再次读取 `/etc/profile` 或 `~/.profile`，因此 Profile 脚本应保持幂等。
- **JSON 编码参数透传**：桌面 `argv` 与会话元数据通过环境变量中的 JSON 传递，避免被 POSIX shell 或 fish 二次分词或转义。
- **Locale 优先级**：优先保留用户显式设置的 Locale 变量；仅当未设置有效 `LANG` 时回退至 `LANG=C.UTF-8`，并将诊断信息记录到 `session-*.log`。

## 4. 环境变量发布边界

| 变量类别 | 发布规则 |
| --- | --- |
| **Locale 与 `PATH`**（`LANG`、`LC_*`、`PATH`） | 由 login shell 初始化，由会话管理器在激活用户服务前发布 |
| **桌面标识**（`XDG_CURRENT_DESKTOP`、`XDG_SESSION_DESKTOP`、`XDG_SESSION_TYPE`） | 由 `.desktop` 元数据提供初始值，由桌面会话管理器确定最终值 |
| **工具包与输入法**（`QT_IM_MODULE`、`XMODIFIERS`、`QT_QPA_PLATFORMTHEME`） | 由用户登录/桌面配置显式指定，仅发布实际配置的变量 |
| **显示端点**（`WAYLAND_DISPLAY`、`DISPLAY`、`XAUTHORITY`） | 合成器创建显示 Socket 后由合成器或会话管理器发布 |
| **临时登录 / Greeter 内部变量**（`XDG_SESSION_ID`、`XDG_VTNR`、`AKARI_*`） | **严禁**发布到全局 `systemd --user` 或 D-Bus 激活环境中 |

### 会话管理器与直接启动的合成器

- **托管桌面会话（GNOME、Plasma、UWSM）**：保持各自原生的会话生命周期（如 `uwsm finalize`、systemd graphical target 与退出清理），Akari 不会在已有会话管理器外再套一层包装。
- **直接启动的合成器会话（如直接启动 Hyprland）**：依赖合成器自身的环境导入机制（如 `dbus-update-activation-environment --systemd`）。注意：若用户自定义配置（如未修改的 end-4 Lua 脚本）采用异步回调并发启动应用，新增回调无法约束上游已提前启动的子进程顺序。

## 5. 实机验收清单

- [ ] 使用 `zsh` 和 `fish` 进行真实 `greetd` 登录：登录配置中导出的变量可传递至桌面，且交互式 `.zshrc` 不会被执行。
- [ ] 含空格路径、引号参数、空参数及 `sh -c` 命令在交接后保持原样。
- [ ] 合成器子进程、新启动的 `systemd --user` 服务与新激活的 D-Bus 服务拥有一致的核心环境变量。
- [ ] 分别测试 UWSM 托管会话与直接启动的 Hyprland 会话，确认注销、重新登录与重载配置时清理正常且无重复自启动。

## 参考资料

- [greetd profile 配置说明](https://man.archlinux.org/man/greetd.5.en)
- [zsh 启动文件](https://zsh.sourceforge.io/Doc/Release/Files.html) 与 [fish 配置说明](https://fishshell.com/docs/current/#configuration)
- [D-Bus 激活环境更新](https://dbus.freedesktop.org/doc/dbus-update-activation-environment.1.html)
- [UWSM 环境与就绪管理](https://github.com/Vladimir-csp/uwsm#readme)
