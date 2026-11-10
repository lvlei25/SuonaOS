# 04 · 任务看板

状态列供 `scripts/spec-status.sh` 统计，使用固定英文值。

| 编号 | 任务 | 状态 | 依赖 | 验收命令 | 备注 |
|---|---|---|---|---|---|
| TASK-01 | 确认诊断通知已静音 | cancelled | — | 用户决定不再验证（2026-11-05），接受现状 | ISSUE-03 / REQ-11 / ADR-20 |
| TASK-02 | 电池检测排除 sudo 误判 | done | — | 复测确认电池存在且健康，误判根因已修 | ISSUE-05 / REQ-12 |
| TASK-03 | 同步 docs/07、08 与 scripts/07、08 到 systemd 方案 | done | — | `docs/` 无旧自启残留 ✓；`bash -n` 3 脚本 ✓；99-verify 输入法段 5/5 ✓ | ISSUE-06 / ADR-04 / 11-05 |
| TASK-04 | `99-verify.sh` 适配已回退字体/主题 | done | — | 回退态 49/49 ✓（含美化段）；定制态分支同样零失败 | ISSUE-07 / ADR-03 / ADR-07 |
| TASK-05 | `bench.sh` + `systemd-analyze` 复测归档 | done | — | `docs/00` 第 9 节含前后对照；boot 25.626s / userspace 6.903s | ISSUE-08 / REQ-16 |
| TASK-06 | 根 README 增加 spec 导航 | done | — | README 含 `spec/` 链接 | — |
| TASK-07 | 供电/电池养护 | done | — | 充电阈值 75/80 已生效；电池健康 100.7%、循环 2 次 | REQ-15 |
| TASK-08 | 决定是否恢复 Inter / JetBrains Mono | done | — | 结论：维持系统默认 Adwaita Sans / Ubuntu Sans Mono，字体包与 fontconfig 保留可随时切回 | REQ-06 / ADR-07 / ADR-26 |
| TASK-09 | 修正「Shell 输入框无法用 fcitx5」过时结论 | done | — | `grep -r '永远无法' docs/` 0 命中 ✓；改为配置取舍表述 | ISSUE-06 / ADR-05 |
| TASK-10 | 记录 Kimpanel 与主题互斥 | done | — | `docs/08` 6.4 节含现象/原因/取舍/切换方法 | ADR-05 |
| TASK-11 | 建立 spec 体系 | done | — | `spec/` 9 文件齐全 | 本批次 |
| TASK-12 | fcitx5 改 systemd 用户服务自启 | done | — | `systemctl --user is-active fcitx5.service` | ADR-04 |
| TASK-13 | 输入法主题切深色 Mocha Blue | done | — | `classicui.conf` 主题值 | ADR-05 |
| TASK-14 | 桌面主题与 Dock 回退 | done | — | gtk-theme = Yaru | ADR-07 |
| TASK-15 | GRUB 超时保持 5s | done | — | 正常分支 timeout=5 | ADR-03 |
| TASK-16 | 登记上游立项报告索引 | done | — | `spec/00-upstream.md` 存在 | ADR-09 |
| TASK-17 | 修复蓝牙耳机连接后不自动播放 | done | — | 断开重连后自动从耳机出声 | ISSUE-14 / ADR-11 |
| TASK-18 | 修复改名导致的 dotfiles 软链断裂 | done | — | 4 个软链有效（与 TASK-35 合并完成） | ISSUE-15 / ADR-12 |
| TASK-19 | 同步文档与 RECOVERY.txt 中的旧路径 | done | — | 仅 ADR-02 保留一处历史记述，其余清零 | ISSUE-15 |
| TASK-20 | 将蓝牙音频排查写入 `docs/99-故障排查.md` | done | — | 2.8 节含根因/两步修复/验收；配置原文与实际逐行一致 ✓ | ADR-11 / ISSUE-14 |
| TASK-21 | 恢复 `avahi-daemon`（撤销阶段 2 的服务精简） | done | — | `systemctl is-active avahi-daemon` = active | ISSUE-16 / ADR-14 |
| TASK-22 | 安装并启用 GSConnect（GNOME 集成） | cancelled | — | 用户要求手机端零安装，方案不适用 | ADR-15 |
| TASK-23 | 手机端装 KDE Connect 并配对 | cancelled | — | 同上 | ADR-15 |
| TASK-24 | 安装 `scrcpy` + `adb` | done | — | `adb version` / `scrcpy --version` 可用 | ADR-15 |
| TASK-25 | 安装 LocalSend 做跨平台文件互传 | cancelled | — | 需手机端 App，违反约束 | ADR-15 |
| TASK-26 | 处理 GSConnect 71 剪贴板缺陷 | cancelled | — | 改用 scrcpy 剪贴板，问题不存在 | ADR-15 |
| TASK-27 | 编写 `docs/11-手机互联.md` | done | — | 文档存在（已按 ADB-only 重写） | ADR-10 |
| TASK-28 | 红米开启调试并完成本机组网 | done | — | `adb devices -l` 显示 `device` | REQ-20 |
| TASK-29 | 验证 scrcpy 投屏 + 反向控制 | cancelled | — | 用户决定不再验证（2026-11-05）；投屏画面已确认 | REQ-20 / ADR-20 |
| TASK-30 | 验证文件互传与剪贴板 | cancelled | TASK-28 | ADR-20：主体已交付，补测取消；当前无 ADB 设备连接 | REQ-20 / ADR-20 |
| TASK-31 | HyperOS 无线调试连接（免 USB 线） | done | — | `192.168.31.196:39959` 为 `device` 状态 | REQ-21 / ISSUE-20 |
| TASK-32 | 卸载用不上的 GSConnect 扩展 | done | — | `apt purge` 已完成，包/目录为空；会话缓存的 `list` 条目注销后消失 | ADR-15 / ADR-26 |
| TASK-33 | 编写 `mobile-connect.sh` 一键连接脚本 | done | — | `bash -n` 通过、`--status` 可用 | REQ-22 / ADR-16 |
| TASK-34 | 创建桌面启动器（双击即投屏） | done | — | `~/.local/share/applications/mobile-connect.desktop` 存在 | REQ-22 |
| TASK-35 | 修复 4 个 dotfiles 断链（ISSUE-15）并加 `mc` 别名 | done | — | 4 个软链有效、`zsh -n` 通过、别名在第 95 行 | ISSUE-15 |
| TASK-36 | 可选：把设备切到固定 5555 端口，长期免输 | blocked | 手机在线 | 11-07 复测 `192.168.31.196:39959` 拒绝连接（无线调试关闭/IP 变更）；需手机端开启后执行 `mobile-connect.sh --tcpip` | REQ-22 / ADR-26 |
| TASK-37 | 修正投屏窗口偏小，按高分屏逻辑像素自适应 | done | — | 窗口 378x840 逻辑像素，`MC_HEIGHT` 可覆盖 | ISSUE-23 / ADR-17 |
| TASK-38 | 升级启动器：快捷操作 / 可见错误 / WM_CLASS / 项目模板 | done | — | `desktop-file-validate` 通过、4 个 Action 可用 | ADR-18 |
| TASK-39 | 安装升级后的启动器到用户目录 | done | — | 4 个 Action、`Terminal=true`、`WM_CLASS=scrcpy` | TASK-38 |
| TASK-40 | GRUB 主题（Vimix 2K） | done | — | `GRUB_THEME` 指向 theme.txt；`grub-script-check` 通过；Windows/recovery 条目保留 | REQ-23 / ADR-24 |
| TASK-41 | Dock 透明 + 顶栏毛玻璃 | done | — | Dock `FIXED/0.5` 生效；扩展已启用（待重登）；99-verify 美化段 3/3 | REQ-24 / ADR-24 |
| TASK-42 | 水系壁纸轮换 | done | — | 4 张 3072×1920；XML 4 static/4 transition；深/浅色均生效；`--list` 可用 | REQ-25 / ADR-25 |
| TASK-43 | 制作 Suona 声音主题 | done | — | 29 个事件音（木腔/瓷击/哨片/低木，含电池 3 个）；`--dry-run/--list/--preview/--restore` 可用；`strace` 证实加载本主题；99-verify 57/0 | REQ-26 / ADR-27 |
| TASK-44 | 电池关键节点提示（20% / 10% / 充满） | done | — | 3 个事件音；UPower `Critical` 5→10；timer 每分钟去重；伪造 sysfs 单测 `full → 幂等 → idle` | REQ-27 / ADR-29 |
| TASK-45 | 深色随日落自动切换 | done | — | 上海 06:15/17:01 计算正确；timer 10min；19:25 实测切到 prefer-dark | REQ-28 / ADR-30 |
| TASK-46 | GTK 圆角覆盖层 | done | — | 移除 9424 行 dark 软链；GTK4/GTK3 14px；`--radius` 可调 | REQ-29 / ADR-30 |
| TASK-47 | 输入法顶栏图标单色化 | done | — | 用户级 `fcitx-pinyin-symbolic.svg` + kimpanel 补丁；`--status` 三项就位，待注销验证 | REQ-30 / ADR-31 |
| TASK-48 | 补齐声音主题缺失事件 | done | — | 29→34；相对 Yaru 仅剩 `warty-startup`（Ubuntu 专用，GNOME 不触发） | REQ-31 / ADR-27 |

## 阻塞与等待
TASK-36 是唯一未闭环项：需手机端开启无线调试（或插 USB）后执行 `--tcpip`。
其余任务均为 `done` 或 `cancelled`，`in_progress` / `deferred` 已归零。

## 已取消（ADR-20）
TASK-01 / TASK-29 经用户决定不再执行，标记 `cancelled` 并保留编号（编号只增不复用）。
