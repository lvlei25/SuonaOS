# 02 · 需求清单

| 编号 | 需求 | 优先级 | 状态 | 验收 | 产物 |
|---|---|---|---|---|---|
| REQ-01 | 基线采集 + 可回滚骨架 | P0 | done | `rollback.sh --list` 可用 | `00-preflight.sh`、`lib/common.sh` |
| REQ-02 | 基础工具链 | P0 | done | `99-verify.sh` 命令项全过 | `01-install-base.sh` |
| REQ-03 | apt/pip/npm/git 镜像加速 | P1 | done | apt 走 TUNA、registry 正确 | `02-network-mirrors.sh` |
| REQ-04 | 启动与运行时性能 | P1 | done | zram、21 单元禁用、sysctl 生效 | `03-perf-tune.sh` |
| REQ-05 | 开发环境 zsh/tmux/vim/node/uv | P1 | done | dotfiles 软链、默认 shell=zsh | `04-devtools.sh` |
| REQ-06 | 中文字体渲染 | P2 | reverted | 已回系统默认 | `05-cjk-fonts.sh` |
| REQ-07 | WhiteSur 桌面主题 | P2 | cancelled | 用户偏好系统默认外观 | `06-theme-whitesur.sh` |
| REQ-08 | macOS 风格 Dock | P2 | cancelled | 已 `reset-recursively` | — |
| REQ-09 | fcitx5 登录自启 | P0 | done | `systemctl --user is-active fcitx5.service` | systemd user unit |
| REQ-10 | 候选框主题（深色圆角） | P1 | done | `Theme=Catppuccin-mocha-blue` 生效 | `08-ime-theme.sh` |
| REQ-11 | 静音 Wayland 诊断通知 | P1 | cancelled | 用户决定不再处理，接受通知出现 | — |
| REQ-12 | 电池 / 供电检测 | P1 | done | `dmidecode -t 22` 与 `BAT0` 均确认电池存在且健康 | `battery-check.sh` |
| REQ-13 | 文档与配置一致 | P0 | done | 旧自启路径 0 残留 ✓；07/08/99 文档已同步 systemd；Shell 结论与 Kimpanel 取舍已更正 | ISSUE-06 / TASK-03/09/10 |
| REQ-14 | 体检脚本适配当前配置 | P1 | done | `99-verify.sh` 49/49 零失败；状态感知，改配置不需改脚本 | ISSUE-07 / TASK-04 |
| REQ-15 | 供电/电池养护 | P2 | done | 充电阈值 75/80 已生效（`charge_start/stop_threshold`） | sysfs / thinkpad_acpi |
| REQ-16 | 开机时间实测归档 | P1 | done | `docs/00` 第 9 节：boot 25.626s、userspace 6.903s、bench 基准全档 | `bench.sh` / ISSUE-08 |
| REQ-17 | Spec 体系 | P0 | done | `spec/` 9 文件齐全 | 本目录 |
| REQ-18 | 蓝牙音频设备连接后自动切换 | P1 | done | 断连重连后默认 sink 落在耳机、已有流迁移 | `pipewire-pulse.conf.d/` |
| REQ-19 | 项目目录改名后的路径一致性 | P0 | done | 4 个软链有效 ✓；RECOVERY.txt / docs/98,99,04,01 / README / rescue.sh 旧路径全清；配置名按 ADR-22 保留 | ADR-12 / ADR-22 |
| REQ-20 | 手机与桌面互联（开源工具，**手机端零安装**） | P1 | done | 连接、投屏画面、一键启动器均已实测；反向控制/剪贴板验证按 ADR-20 取消 | `docs/11-手机互联.md` |
| REQ-21 | 无线互联（免 USB 线） | P2 | done | `adb connect` 成功且 `device` 状态，无线投屏进程与 server 均在运行 | HyperOS 无线调试 |
| REQ-22 | 一键连接投屏（免去每次手输命令） | P1 | done | 启动器 4 个 Action + `mc` 别名 + 端口记忆全部落盘验收 | `scripts/mobile-connect.sh` |
| REQ-23 | GRUB 引导菜单美化 | P2 | done | Vimix 2K + 白色图标；`grub.cfg` 语法通过；`preboot-check` 24/0/0；双系统条目保留 | `docs/13` / ADR-24 |
| REQ-24 | Dock 与顶栏透明度美化 | P2 | done | Dock `FIXED/0.5` 即时生效；顶栏 Blur my Shell 参数已写（待注销重登确认） | `docs/13` / ADR-24 |
| REQ-25 | 水系主题桌面壁纸 | P2 | done | 14 张 3072×1920（Wikimedia CC，湖/瀑布/海滩/港湾）；每 30 分钟轮换；深/浅色均生效；署名 `CREDITS.txt` | `docs/14` / ADR-25 |
| REQ-26 | 系统提示音主题（Suona 木腔） | P2 | done | 29 个事件音（含电池 3 个）、ffmpeg 本地合成零素材；峰值归一 -3.5 dB；`strace` 证实 libcanberra 读取本主题；99-verify 57/0 | `docs/15` / ADR-27 |
| REQ-27 | 电池关键节点提示（20% / 10% / 充满） | P2 | done | `battery-low`/`battery-caution` 由 gsd-power 自动触发；充满由 user timer 按 `charge_control_end_threshold` 判定；99-verify 57/0 | `docs/16` / ADR-29 |
| REQ-28 | 深色模式随日落自动切换 | P2 | done | NOAA 本地算日出日落；10 分钟 timer；同时切 color-scheme 与 gtk-theme；状态去重 | `docs/17` / ADR-30 |
| REQ-29 | 桌面与部分软件圆角优化 | P3 | done | GTK4 窗口/弹层 14px、GTK3 外框；Shell 层按 ADR-07 不动 | `docs/17` / ADR-30 |
| REQ-30 | 输入法顶栏图标与系统风格统一 | P2 | done | 用户级 symbolic 图标 + kimpanel `createSymbolicIcon` 补丁；需注销生效 | `docs/17` / ADR-31 |
| REQ-31 | 补齐音效主题缺失事件 | P3 | done | 新增 desktop-login/logoff、dialog-question、message-new-email、system-ready，29→34 | `docs/15` / ADR-27 |

## 变更记录
- 2026-11-03 REQ-07/08 `done` → `cancelled`：用户偏好系统自带 Dock。
- 2026-11-03 REQ-06 `done` → `reverted`：卡顿排查期间回退，非性能原因。
- 2026-11-04 REQ-09 实现方式改 systemd（ADR-04）。
