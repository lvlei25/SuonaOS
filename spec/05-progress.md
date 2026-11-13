# 05 · 进度日志

只追加，不改写历史行。格式：时间 | 事件 | 关联

| 时间 | 事件 | 关联 |
|---|---|---|
| 11-03 20:05 | 环境探测：Ubuntu 26.04 / GNOME 50 Wayland / T14 Gen5 | — |
| 11-03 20:14 | 基线采集 26 项；开机 26.4s、36 服务 | REQ-01 |
| 11-03 20:56 | 免密 sudo 配置；apt 换 TUNA | REQ-03 |
| 11-03 20:58 | zram 6.9G、21 单元禁用、sysctl、GRUB | REQ-04 |
| 11-03 21:02 | 开发环境，默认 shell 改 zsh | REQ-05 |
| 11-03 21:03 | Inter/JetBrains + fontconfig | REQ-06 |
| 11-03 21:05 | WhiteSur 全套 + Dock 定制 | REQ-07/08 |
| 11-03 21:07 | 48 项校验全过 | — |
| 11-03 21:45 | preboot-check / rescue / RECOVERY.txt | — |
| 11-03 22:00 | 发现 Windows 双系统，GRUB 保留 5s | ADR-03 |
| 11-03 22:26 | 重启后开机 5min、迟缓 20 倍，定位 CPU 锁 544MHz | ISSUE-01 |
| 11-03 23:0x | 回退主题/字体/Dock/输入法环境；建 bench.sh | ADR-07 |
| 11-04 | 完整断电后性能恢复（EC/SMU 复位） | ISSUE-01 关闭 |
| 11-04 19:55 | 输入法主题切 Mocha Blue，装 66 套 | REQ-10 |
| 11-04 20:xx | 反馈 fcitx5 不自启 + Wayland 诊断提示 | ISSUE-02/03 |
| 11-04 | 改 systemd 用户服务自启成功 | ADR-04 |
| 11-04 | 装 Kimpanel 致主题失效；fcitx5 侧禁用后恢复 | ADR-05 |
| 11-04 | 电池检测：SMBIOS Type 22 无记录，待排除误判 | ISSUE-05 |
| 11-04 | 阅读立项报告 v1.0，登记差异 | ADR-09 |
| 11-04 | 建立 spec 体系（9 文件 + status 脚本） | REQ-17 |
| 11-04 | 依据立项报告 v1.0 编写 `spec/suonaos/` 产品级 spec 计划（6 文件） | ADR-09 / ADR-10 |
| 11-04 | 新增 `suonaos/06-milestone-audit.md` 可填写核验表，供 S-10/S-11 使用 | SDEC-04 输入 |
| 11-05 | 蓝牙耳机连接后不自动播放：定位 WirePlumber `default.configured.audio.sink` 锁定 + 流不迁移 | ISSUE-14 |
| 11-05 | 清除锁定状态 + 启用 `module-switch-on-connect`，用户确认修复完成 | REQ-18 / ADR-11 |
| 11-05 | 项目目录改名 `linux-tune` → `linux-tune_SuonaOS`，立项报告 HTML 移入 `spec/` | ADR-12 |
| 11-05 | 核验发现 4 个 dotfiles 绝对路径软链断裂，登记为 ISSUE-15 | ISSUE-15 |
| 11-05 | 手机互联环境探测：互联工具均未装、`avahi-daemon` 被阶段 2 禁用、ufw 未启用、Wi-Fi 192.168.31.225 | REQ-20 |
| 11-05 | 查证 GSConnect 71 在 GNOME 50 剪贴板缺陷（Launchpad #2172008，需 v74） | ISSUE-17 / ADR-13 |
| 11-05 | 编写 `docs/11-手机互联.md`，登记 REQ-20 / TASK-21~27 / ISSUE-16,17 / ADR-13,14 | REQ-20 |
| 11-05 | 用户执行块 1：avahi 恢复 enabled+active，GSConnect/scrcpy/adb 已装，MTP 后端未装 | REQ-20 |
| 11-05 | 用户明确：手机为红米（HyperOS），**不接受安装第三方 App** → 方案改 ADB-only | ADR-15 |
| 11-05 | 弃用 GSConnect/KDE Connect/LocalSend；`docs/11` 重写为 ADB-only，复用已装工具零新增安装 | ISSUE-19 / REQ-20 |
| 11-05 | 新增 REQ-21 无线互联、TASK-28~32；TASK-22/23/25/26 标记 cancelled | ADR-15 |
| 11-05 | 无线连接尝试失败；诊断 TCP 39959 可连、5555 不通，曾误判为端口用途混淆（ISSUE-20） | REQ-21 / TASK-31 |
| 11-05 | 无线连接成功：`192.168.31.196:39959 device product:manet model:23117RK66C transport_id:2` | REQ-21 / TASK-31 |
| 11-05 | 读取设备参数：Android 16、安全补丁 2026-09-01、物理 1440x3200（覆写 1080x2400） | REQ-20 |
| 11-05 | 更正 ISSUE-20 根因（39959 实为连接端口），登记 ISSUE-21 记录误判教训 | 排查原则 |
| 11-05 | scrcpy 无线投屏进程与 server 均在运行，画面已出；确认手机 `navigation_mode=2`（全手势） | TASK-29 / REQ-20 |
| 11-05 | 用户反馈画面无返回/主页按钮；查明为 scrcpy 无工具栏 + 手机全手势导航，文档补快捷键表 | TASK-29 |
| 11-05 | 用户要求免去每次手输连接命令；实测 `adb mdns services` 为空，HyperOS 不广播 ADB 服务 | ADR-16 / REQ-22 |
| 11-05 | 编写 `scripts/mobile-connect.sh`（记忆地址 + 端口单次覆盖 + 固化投屏参数），`bash -n` 与 `--status` 通过 | TASK-33 / REQ-22 |
| 11-05 | 新增 ADR-16、REQ-22、TASK-33~36；`docs/11` 补 5.2 一键连接章节 | ADR-16 |
| 11-05 | 用户反馈投屏窗口偏小；查明 `--max-size 1080` 压窄竖屏 + GNOME 200% 缩放（逻辑 1536x960） | ISSUE-23 |
| 11-05 | 脚本改为显式窗口尺寸 + 按视频比例自适应（默认 378x840），`MC_HEIGHT` 可覆盖；新增 ADR-17、5.3 章节 | TASK-37 / ADR-17 |
| 11-05 | 用户指出启动器需一并修改；发现旧版无快捷操作、`Terminal=false` 会吞掉端口变更提示 | ADR-18 / TASK-38 |
| 11-05 | 新增启动器模板（4 个 Action + WM_CLASS + 路径占位）与脚本 `--port-prompt`；`desktop-file-validate` 通过 | TASK-38 / ADR-18 |
| 11-05 | 用户已执行两块命令：4 个软链有效 + `mc` 别名、升级版启动器安装到位，三项语法校验通过 | TASK-35/39 |
| 11-05 | 批量修正 `RECOVERY.txt`(3)、`docs/98`(2)、`docs/02`(1)、`ADR-02`、`06-milestone-audit` 旧路径 | TASK-19 / ISSUE-15 |
| 11-05 | ISSUE-15 收口，TASK-18/19/35/39 标记 done | REQ-19 / ADR-12 |

| 11-05 | 用户贴回 `dmidecode -t 22`：SMP 5B11H56415 / 52.57 Wh / 2026-01 产；推翻「无电池」结论 | ISSUE-05 |
| 11-05 | 复测 `BAT0` 存在、upower 有 `battery_BAT0`；健康 100.7%、循环 2 次、阈值 75/80 | REQ-12/15 |
| 11-05 | 修复 `battery-check.sh` 静默降级缺陷（ISSUE-24）；更正全部「无电池致 CPU 锁频」因果推断 | ISSUE-24 / ADR-14 |
| 11-05 | REQ-12/15、TASK-02/07、M4 收口为 done；ISSUE-05 resolved | REQ-12 |

| 11-05 | 用户决定剩余 2 项（TASK-01 通知静音确认 / TASK-29 反向控制验证）不再执行 | ADR-20 |
| 11-05 | 范围裁剪：REQ-11 cancelled、ISSUE-03 closed、REQ-20/21/22 done；M3 完成度 60%、P0~P2 重排 | ADR-20 |
| 11-05 | TASK-03 完成：07/08 脚本与文档同步到 systemd 自启；修 99-verify 必红项；docs/07/08/99 共 3 篇重写相关章节 | ISSUE-06 / ADR-04 |
| 11-05 | 99-verify 输入法段 5/5 通过；汇总 38/42，剩余 4 项均为回退后的过时断言（GRUB 5s、字体 3 项），归 TASK-04 | ISSUE-07 |

| 11-05 | TASK-04 完成：99-verify 改状态感知双分支（GRUB 双系统 / 字体定制态·回退态 / 主题定制态·回退态）；回退态 45/45、定制态 mock 45/45 | ISSUE-07 / REQ-14 |
| 11-05 | 实测开机 25.626s（firmware 9.182 + loader 7.191 + kernel 0.984 + initrd 1.365 + userspace 6.903） | REQ-04 |
| 11-05 | 确立「校验脚本状态感知」原则并写入 ADR-21；同步 README 结果表与 docs/99 检查项数 | ADR-21 |

| 11-06 | 性能复测归档 `docs/00` 第 9 节：boot 25.626s、userspace 6.903s（−38%）、python 0.13s、sha256 1036MB/s；总时长仅 −0.78s 因 GRUB 保留 5s | TASK-05 / ISSUE-08 / REQ-16 |
| 11-06 | TASK-09/10：纠正「Shell 输入框无法用 fcitx5」绝对化结论为配置取舍；`docs/08` 6.4 补 Kimpanel 互斥全说明 | ISSUE-06 / ADR-05 |
| 11-06 | TASK-20：`docs/99` 2.8 补蓝牙音频排查；顺带修 GRUB「应为 1」、WhiteSur 章节、输入法自启说明 | ADR-11 / ISSUE-14 |
| 11-06 | 修急救文档旧路径（RECOVERY.txt / docs/98,99,04,01 / README / rescue.sh）；区分配置名不误改，立 ADR-22 | REQ-19 / ADR-22 |
| 11-06 | `03-perf-tune.sh` 加 13 单元保护白名单 + 4 步依赖检查流程，单测通过；ISSUE-18 resolved | ADR-14 / ISSUE-18 |
| 11-06 | TASK-30 按 ADR-20 收口 cancelled；M3 100%、REQ-13/16/19 done、ISSUE-06/08/18 resolved | ADR-20 |

| 11-06 | 修复 dry-run 空回滚记录致体检误报（ISSUE-25 / ADR-23）；复验 24/0/0 与 45/0 | ADR-23 |
| 11-06 | M5 归档交付：`docs/12-交付报告.md` 落盘；M0~M5 全部 100%，看板 in_progress/planned 归零 | M5 |

| 11-06 | 产品级 S-12 完成：定义 8 步清单 v1（量化判据 + 四状态），新增 `scripts/step-verify.sh`；原型机实测 PASS 6/8、FAIL 0、2 步工具缺失 | S-12 / A-21 |
| 11-06 | S-11 核验完成：SM-1 = `partial`（6/8）；SM-0 因缺 5 类外部凭证标 `blocked`，A 部分全 `unknown`；建 `06-milestone-audit-2026-11-06.md` | S-10/S-11 |

| 11-06 | GRUB 美化：Vimix 2K + white 图标装入 `/usr/share/grub/themes`；GFXMODE 2560x1440；超时仍 5s，Windows/recovery 条目保留 | REQ-23 / TASK-40 / ADR-24 |
| 11-06 | Dock 透明 `FIXED/0.5` 即时生效；顶栏装 Blur my Shell 并写入 brightness 0.6 / sigma 30，待注销重登 | REQ-24 / TASK-41 |
| 11-06 | `99-verify.sh` 新增「美化」段 3 项（状态感知），体检 45→48 全过；backup `20261106-075444` | ADR-21 / ADR-24 |

| 11-06 | 水系壁纸：Wikimedia Commons 取 4 张（CC BY/BY-SA/FAL），裁切 3072×1920，XML 每 30 分钟轮换，深/浅色均生效 | REQ-25 / TASK-42 / ADR-25 |
| 11-06 | 生成 `CREDITS.txt` 署名清单；新增 `scripts/10-wallpaper-water.sh`（`--interval` / `--list`）；体检 48→49 | ADR-25 |

| 11-06 | Chromium 无法打开：定位为 SingletonLock 残留（PID 已死）+ 缺 zenity 致静默退出；删锁后可持续运行；snap 已刷新至 3580 | ISSUE-27 / docs/99 §2.9 |

| 11-07 | TASK-08 收口：维持系统默认字体 Adwaita Sans / Ubuntu Sans Mono，不恢复 Inter/JetBrains Mono；字体包与 fontconfig 保留可切回 | ADR-26 / REQ-06 |
| 11-07 | TASK-32 收口：`apt purge gnome-shell-extension-gsconnect`(v71) 完成，包/目录已空；未做 autoremove（会连带 16 个包） | ADR-26 / ADR-15 |
| 11-07 | TASK-36 复测失败：`192.168.31.196:39959` connection refused，转 `blocked` 待手机开启无线调试 | ADR-26 / REQ-22 |
| 11-07 | 顺带发现 9 个脚本无执行位（README 的 `./scripts/*.sh` 全部 Permission denied），`chmod +x` 修复，体检 49/0 | ISSUE-28 |
| 11-08 | 新增 Suona 声音主题：ffmpeg `aevalsrc` 合成 26 个事件音（木腔/瓷击/哨片/低木），零第三方素材 | REQ-26 / TASK-43 / ADR-27 |
| 11-08 | 首版按波形系数估算音量，实测 reed −19 dB、快门 −0.5 dB，改为逐文件峰值归一（默认 −3.5 dBFS） | ADR-27 |
| 11-08 | `strace` 证实 libcanberra 打开 `Suona/stereo/bell.oga`（非回落）；99-verify 新增声音段 4 项，49→53 | ADR-21 / ADR-27 |
| 11-08 | 音量不匹配诊断：GNOME 50 无系统音效音量键，libcanberra 流 `media.role=event` 与应用共享 sink 音量 | ADR-28 |
| 11-08 | WirePlumber `stream.rules` 给 event 设 `target.volume` 实测无效（仍 100%，restore 记录为空），配置已删除 | ADR-28 |
| 11-08 | 改为生成端衰减 `SYS_DECAY_DB=-6.5`：提示音峰值 −3.5→−10.0 dBFS，与应用内容拉开约 9 dB；`--decay` 可调 | ADR-28 / REQ-26 |
| 11-08 | 99-verify 新增「峰值 ≤ −8 dBFS」裁决项，53→54；蓝牙 sink 音量被 AVRCP 抖动已还原 0.30 | ADR-28 |
| 11-08 | 实测「电量变化触发提示音」不成立：90s 内 0 音频流、0 power_supply 事件，upower 仅 30s 轮询 | ADR-29 |
| 11-08 | 按用户选择实现关键节点提示：补 battery-low/caution（gsd-power 自动触发）+ battery-full（user timer）；UPower Critical 5→10 | REQ-27 / ADR-29 |
| 11-08 | 伪造 sysfs 单测 `full → 幂等 → idle` 通过；99-verify 新增电池段 3 项，54→57 | ADR-29 |
| 11-08 | `--install` 重启 upower 后 BAT0 从 sysfs 消失（ISSUE-29）；`udevadm trigger` 无效，重载 `thinkpad_acpi` 恢复，阈值与健康度无损 | ISSUE-29 |
| 11-08 | `13-battery-alert.sh` 新增 `restart_upower_safe()`：重启后检测 `BAT*`，缺失自动重载模块自愈 | ISSUE-29 / ADR-29 |
| 11-08 | 「电量变化提示音」定位为**阵发**：注册集中在 upower 重启后（10:20，11 次）与挂起前准备（10:35:38 前，3 次）；秒数分布均匀，与 timer 无相关性 | ISSUE-29 |
| 11-08 | 三窗口监控（90/60/100 s）均 0 音频流、0 remove；唤醒后无电池重枚举，确认非持续故障，监控已撤 | ISSUE-29 |
| 11-08 | 新增 `14-auto-dark.sh`：NOAA 本地算日出日落（上海 06:15/17:01），10 分钟 timer，实测切到 prefer-dark | REQ-28 / ADR-30 |
| 11-08 | 发现 `gtk.css` 硬链 9424 行 dark 副本导致 GTK4 永远暗色，已移除并备份（backup/20261108-192059） | ADR-30 |
| 11-08 | 新增 `15-rounding.sh`：GTK4 窗口/弹层 14px + GTK3 外框；Shell 层按 ADR-07 不动 | REQ-29 / ADR-30 |
| 11-08 | 输入法图标：提供 `fcitx-pinyin-symbolic.svg` + kimpanel `createSymbolicIcon` 补丁，幂等脚本 `16-ime-icon.sh`，待注销验证 | REQ-30 / ADR-31 |
| 11-08 | 声音主题补齐 5 个事件（登录/登出/疑问/邮件/就绪），29→34；相对 Yaru 仅剩 `warty-startup` | REQ-31 / ADR-27 |
| 11-08 | 99-verify 新增「日光与圆角」段 3 项、声音阈值 20→30，57→60 零失败 | ADR-21 |
| 11-08 | Shell 圆角：新建叠加式主题 `Suona-Round`（@import Yaru + 5 条圆角），即时生效；主题段改三态断言 | REQ-29 / ADR-32 |
| 11-08 | 性能复核（docs/00 §9.6）：python 0.11s、sha256 1062 MB/s、磁盘 2081 MB/s，均不劣于 11-05 基线 | REQ-16 |
| 11-08 | 新增 timer 开销实测：电池 63ms/60s、日落 110ms/600s，合计 <0.13% 单核；开机 +0.17s 源于 apt-daily | REQ-16 |
| 11-08 | 电池 timer 间隔 60s→300s（`AccuracySec` 10→30），合计占用降至 <0.05% 单核；充满提示最多延迟 5 分钟 | REQ-16 / REQ-27 |
| 11-08 | 体检发现 `fcitx5.service` 因 kimpanel 重载被 `--replace` 踢出托管（ISSUE-30），重启服务恢复，输入法段 5/5 | ISSUE-30 / ADR-31 |
| 11-08 | 快捷设置「键盘」无响应：定位为 upowerd 键盘背光句柄在挂起后失效（非屏幕亮度），重启 upower 后 Set/Get 往返正常 | ISSUE-31 |
| 11-08 | 新增 `17-sleep-hook.sh`：`/etc/systemd/system-sleep/50-suona-upower` resume 按需自愈（仅 KbdBacklight 失效时重启 + BAT0 兜底）；实机验证通过 | ISSUE-31 / ADR-29 |
| 11-08 | 99-verify 新增「挂起恢复 hook」项，60→61 零失败 | ADR-21 |
| 11-09 | WorkBuddy 无法启动：`/opt/WorkBuddy/chrome-sandbox` 缺 setuid（0755），Electron 因无可用沙箱 FATAL 退出；`chmod 4755` 后正常（11 进程） | ISSUE-32 |
| 11-09 | 同批排查发现 `/opt/baidunetdisk/chrome-sandbox` 同为 0755，已修复；99-verify 新增 Electron 沙箱段，61→62 | ISSUE-32 |
| 11-11 | 手机互联不可用：ARP 显示手机在线但 5555/39959 端口全关，判定为无线调试关闭（非故障）；`mobile-connect.sh --status` 新增三段自诊断（ARP 可达 / 端口开放 / adb 握手），两条分支实测通过 | REQ-22 |
| 11-11 | 新增 `18-mobile-file.sh`（`--push/--pull/--ls/--status/--to`），补 scrcpy 只能「拖入」不能「拖出」的缺口；实测推送 hostname、拉回内容一致后清理 | REQ-22 |
| 11-11 | 拖放无反应根因：SDL2 Wayland 后端未实现 `SDL_DROPFILE`；新增 `--x11` 切 XWayland，并按 `Xft.dpi` 换算窗口尺寸（378×840 → 756×1680），修复切后端后窗口变小 | REQ-22 / TASK-37 |
| 11-11 | 新增 `19-mobile-share.sh`：push + `content://` + SEND intent 把文件交给手机 App；能读 `mCurrentFocus` 时直发前台包名，否则退回分享面板；实测 PNG 弹出成功 | REQ-22 |
| 11-11 | 投屏中途黑屏：根因为 `screen_off_timeout=15000` 且未插电时 `stay_on_while_plugged_in=7` 无效；改为投屏期间拉满超时 + trap/`--stop` 双路径恢复，实测 15000→2147483647→15000 | REQ-22 |
| 11-11 | 启动器同步：`mobile-connect` 增加 x11 Action；新增 `mobile-share.desktop`（`--share %F`，支持拖文件到图标），桌面放置并标记 trusted；两份模板与文档同步 | REQ-22 / ADR-18 |
| 11-11 | 启动器启动窗口偏小：`WINDOW_HEIGHT` 默认由 840 改为 `auto`（xrandr 物理高 ÷ Xft.dpi 缩放 − 80），本机 378×840 → 396×880 | REQ-22 / TASK-37 |
| 11-11 | 仍偏小 → 留白 80 收窄到 40，396×880 → **414×920**；新增 `MC_FULLSCREEN=1` 全屏启动 | REQ-22 / TASK-37 |
| 11-11 | 熄屏真因是**主机** idle-delay=300s（5 分钟黑屏锁屏），非手机；改用 `systemd-inhibit --what=idle:sleep` 投屏期间阻止，退出自动释放 | REQ-22 / ADR-18 |
| 11-11 | 顺带查明手机 `screen_off_timeout` 原值仅 **15 秒**，脚本投屏中设 `2147483647`、退出恢复；`stay_on_while_plugged_in` 已置 7 | REQ-22 |
| 11-12 | 地址漂移治理：新增 `--recover`（USB 一键 `tcpip 5555` 并记住 WLAN IP）、`--scan`（并发扫网段 5555，实测 8.1s）；自动模式在 5555 直连失败时兜底扫描 | REQ-22 / TASK-36 |
| 11-12 | 启动器改为手动填地址：`--port-prompt` 同时询问 IP 与端口（回车沿用、`q` 取消），Action 更名「填写 IP 和端口…」；命令行支持 `IP:端口` 完整写法 | REQ-22 / ADR-18 |
| 11-12 | 新增 `18-mobile-file.sh --find`：按关键词搜五个常用目录并编号拉取；修复 `adb shell` 吞 stdin 导致「选编号却全部拉取」；新增启动器 `mobile-pull.desktop` | REQ-22 / ADR-18 |
| 11-12 | 拉取后自动 `xdg-open` 打开目标目录，`--no-open` 可关；顺带修掉 `--help` 因 `usage()` 定义晚于调用而报「未找到命令」的老 bug | REQ-22 |
| 11-12 | 拉取目录改用 `xdg-user-dir DOWNLOAD`（中文环境 `~/下载`），不再写死 `~/Downloads`，避免文件落到没人看的目录 | REQ-22 |
| 11-13 | 壁纸扩到 14 张：从 Wikimedia Featured pictures 四类（湖/瀑布/海滩/水体）取 10 张，统一裁切 3072×1920，CREDITS 追加授权，XML 更新为 14 static/14 transition | REQ-25 / TASK-42 |

## 待补
TASK-36（需手机在线）、S-10 外部凭证、S-13~S-16 产品裁决与上游 v1.1 修订，
均不阻塞技术交付。
