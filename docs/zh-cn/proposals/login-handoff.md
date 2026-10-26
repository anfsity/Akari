# 原生登录画面交接

原生登录画面在两个阶段协调视觉过渡与 VT 控制权：在登录界面的 Sway 合成器启动前，以及在已通过身份认证的用户桌面启动前。

## 1. 启动与交接边界

| 过渡阶段 | 负责模块 | 交接行为 |
| --- | --- | --- |
| **登录界面 Sway 启动前** | `scripts/splash.sh` + `akari-splash kms` | 先启动私有 D-Bus 并等待后端就绪，再运行 `akari-splash kms`；待渲染进程退出并释放显示控制权后启动 Sway。同时保存静态快照（`splash.png`），在 Flutter 加载期间由 `swaybg` 作为背景展示。 |
| **用户桌面启动前** | 用户侧启动器（`session_launch.rs`） | 登录界面退出后，初始化 `startup-*.log` 与 `session-*.log`，运行 `akari-splash kms`，随后直接 `exec` 桌面命令，使桌面保留启动器的进程 PID 与退出码。 |

- 收到退出信号（`SIGINT`、`SIGTERM`）或启动器退出时，会一并终止并回收子进程。
- 身份验证仍在后端 Actor 中执行，不占用 DRM master 权限。

## 2. 渲染与 KMS 生命周期

`akari-splash` 是独立编译的 Rust 程序，内嵌角色立绘 PNG 与 Quicksand 字体：

- **统一 CPU 渲染器**：桌面窗口预览（`akari run splash`）与 KMS 输出共用同一套渲染逻辑，按输出分辨率缓存缩放后的图像与字形图层。
- **背景与展示时长**：默认纯黑背景（`#000000`），从首帧呈现起默认最短保持 `3` 秒（可通过 `AKARI_SPLASH_DURATION` 调整，设为 `0` 取消保持；`akari run splash` 则持续显示至手动关闭）。
- **多显卡与多屏 KMS 支持**：通过 `libseat`（logind/seatd）管理会话席位，枚举所有主 DRM 节点、已连接输出与活动 CRTC（不硬编码显卡编号），按各屏幕原生分辨率创建并映射 XRGB dumb buffer（镜像输出共享同一缓冲区）。
- **资源释放与末帧保持**：在正常退出、异常、终止或席位撤销时，先停止绘制再释放资源与席位控制权。优先使用 `CLOSEFB`（旧内核回退至 `RMFB`）保留最后一帧画面，直至下一个合成器接管显示模式。

## 3. 终端清理与日志保障

- **非阻塞降级**：启动画面出错时仅写入 `lifecycle.log` / `session-*.log`，不会阻断正常登录流程；PTY 终端不会进入 KMS 路径。
- **擦除终端残留文本**：KMS 渲染器释放席位前，以及 Sway 退出后由持有 VT 的启动器运行 `akari-splash clear`，都会主动清空终端文本与回滚缓冲，避免合成器切换间隙闪现控制台文字。

## 4. 实机硬件验收清单

在真实物理 VT 上分别验证两段过渡（进入登录界面 Sway 前、进入用户桌面前）：

- [ ] 不同显卡驱动、混合分辨率显示器以及扩展/镜像多屏布局。
- [ ] 启动画面展示期间及合成器启动过程中的 VT 切换。
- [ ] 渲染进程被终止、缺少 DRM 设备、合成器启动失败以及从桌面注销退出。
- [ ] 桌面退出后无残留 `akari-splash` 进程、无 DRM master 冲突、无残留旧帧或控制台启动日志。

## 参考资料

- [DRM 主节点与帧缓冲生命周期](https://docs.kernel.org/gpu/drm-uapi.html)
- [libseat API](https://git.sr.ht/~kennylevinsen/seatd/tree/master/item/include/libseat.h)
- [greetd 会话协议](https://manpages.debian.org/testing/greetd/greetd-ipc.7.en.html)
