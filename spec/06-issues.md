# 06 · 问题登记

| 编号 | 问题 | 状态 | 根因 | 处理 / 结论 | 关联 |
|---|---|---|---|---|---|
| ISSUE-01 | 重启后开机 5min、迟缓 20 倍 | resolved | CPU 锁 544MHz，EC/SMU 状态，非软件配置 | 完整断电后恢复 | — |
| ISSUE-02 | fcitx5 不自启 | resolved | im-launch 在 Wayland 不启守护进程；`-d --replace` 不稳 | 改 systemd user service | ADR-04 |
| ISSUE-03 | Wayland 诊断通知反复弹 | closed | 禁用 kimpanel 后扩展连不上服务 | 用户决定不再处理，接受通知出现（ADR-20）；如复现按 `docs/07` 处理 | REQ-11 |
| ISSUE-04 | Kimpanel 致候选框主题失效 | resolved | Kimpanel 接管绘制，绕过 classicui | fcitx5 侧禁用 kimpanel | ADR-05 |
| ISSUE-05 | 「电池未识别」误判 | resolved | 早期 `battery-check.sh` 在免密 sudo 失效时静默降级，`dmidecode -t 22` 输出为空，被误读成「固件无电池记录」；当时 `/sys/class/power_supply/` 也恰未枚举到 BAT0 | 复测确认：DMI Type 22 完整、BAT0 存在、upower 有 `battery_BAT0`；脚本已改为显式报错 | REQ-12 / TASK-02 |
| ISSUE-24 | 检测脚本权限降级被静默吞掉 | closed | `SUDO="sudo -n"; $SUDO true 2>/dev/null \|\| SUDO=""` 把提权失败静默降级，导致只读数据缺失被当成阴性结论 | `battery-check.sh` 改为 sudo 不可用时明确告警，并对空输出不做结论 | 排查原则 |
| ISSUE-06 | 文档与配置漂移 | resolved | 自启改 systemd、主题/字体回退后多份文档未同步 | TASK-03/09/10/20 全部完成；07/08/99/98/04/01、README、RECOVERY.txt 已同步 | REQ-13 |
| ISSUE-07 | 99-verify.sh 4 项失败 | resolved | 决策变更（ADR-03 双系统 5s、ADR-07 回退字体/主题）后校验未同步 | 改状态感知双分支，回退态/定制态现在 49/49 零失败 | REQ-14 / TASK-04 |
| ISSUE-08 | 开机优化收益未复测 | resolved | 首次重启受 CPU 锁频干扰，数据无效 | 断电复位后重跑：boot 25.626s / userspace 6.903s（−38%）；总时长仅 −0.78s 因 GRUB 保留 5s。`docs/00` 第 9 节 | REQ-16 / TASK-05 |
| ISSUE-09 | GRUB 1s 优化撤销 | closed | 双系统需保留菜单 | 保持 5s | ADR-03 |
| ISSUE-10 | 用户偏好变更 | recorded | 偏好系统自带 Dock 与默认外观 | REQ-07/08 改 cancelled | ADR-07 |
| ISSUE-11 | classicui.conf 疑似被 autosave 覆盖 | resolved | 实为进程切换未重载，配置完好 | 改主题后 `systemctl --user restart fcitx5.service` | — |
| ISSUE-12 | 立项报告内部矛盾与过期排期 | open | 08 章修订后 9.1/11 未同步；指标口径未定义 | 登记于 `spec/00-upstream.md` | ADR-09 |
| ISSUE-13 | Spec 体系一度未落盘 | closed | 只生成命令块未执行（ADR-08 执行模式） | 单块命令一次建齐 | REQ-17 |
| ISSUE-14 | 蓝牙耳机连接后不自动播放 | resolved | WirePlumber 持久化了手动固定的默认输出 `default.configured.audio.sink`；且已有播放流不迁移 | 删除 `configured` 锁定项 + `module-switch-on-connect`，用户确认修复 | REQ-18 / ADR-11 |
| ISSUE-15 | 项目目录改名致 4 个 dotfiles 软链断裂 | resolved | dotfiles 用绝对路径软链，目录 `linux-tune` → `linux-tune_SuonaOS` 后目标失效 | 4 个软链已重链并校验有效；`docs/98`、`docs/02`、`RECOVERY.txt`、`ADR-02`、`06-milestone-audit` 旧路径已同步 | ADR-12 / TASK-18/19/35 |
| ISSUE-16 | `avahi-daemon` 被禁用，阻断 mDNS 设备发现 | resolved | 阶段 2 服务精简把 `avahi-daemon.service/.socket` 一并禁用 | 已恢复 enabled+active，脚本加白名单（ADR-14）；ADB-only 方案下不再依赖它，但保留修复 | ADR-14 / TASK-21 |
| ISSUE-17 | GSConnect 71 在 GNOME 50 剪贴板插件失效 | cancelled | Ubuntu 26.04 打包版本落后，需 v74 | 用户要求手机端零安装 → 弃用 GSConnect，改用 scrcpy 剪贴板，问题不适用 | ADR-15 |
| ISSUE-19 | 互联方案与「手机端零安装」约束冲突 | resolved | 初版选型以 KDE Connect 协议为主，必须在手机端装 App | 改为 ADB-only（手机只需系统自带 USB 调试），已装桌面工具复用，零新增安装 | ADR-15 / REQ-20 |
| ISSUE-20 | `adb connect 192.168.31.196:39959` 首次失败 | resolved | **初判有误**：曾把 39959 当作配对端口；实测该端口就是连接端口（现为 `device` 状态）。真实原因指向首次未完成配对或无线调试会话未就绪（锁屏 / HyperOS 自动关闭） | 重新连接后成功；`adb devices -l` 显示 `device product:manet model:23117RK66C transport_id:2` | REQ-21 / TASK-31 |
| ISSUE-21 | 排查中出现「端口用途」误判 | closed | 仅凭端口号形态推断用途，未等握手日志佐证 | 结论被实测证伪后已更正文档；今后端口用途以界面文字 + `ADB_TRACE` 为准，不靠端口数字猜 | 排查原则 |
| ISSUE-22 | 投屏画面无返回/主页按钮（用户反馈） | resolved | 非故障：scrcpy 是纯画面窗口无工具栏；手机 `navigation_mode=2` 全手势导航，画面本身也无三键 | 文档补 scrcpy 快捷键表；如需三键，手机设置切「经典三键导航」 | TASK-29 / REQ-20 |
| ISSUE-23 | 投屏默认窗口偏小（用户反馈） | resolved | `--max-size 1080` 对竖屏限制的是高度，宽度按比例仅剩 486；且窗口默认跟随视频尺寸。叠加 GNOME 200% 缩放（逻辑 1536x960）更显小 | 去掉 1080 限制、显式 `--window-width/height`、按视频比例自适应；默认 378x840，支持 `MC_HEIGHT` 覆盖 | ADR-17 / TASK-37 |
| ISSUE-18 | 服务精简与按需功能冲突（结构性问题） | resolved | 阶段 2 按「桌面机不需要」批量禁用 21 个单元，未考虑后续功能依赖 | `03-perf-tune.sh` 加 `PROTECTED_UNITS` 硬约束（13 个单元）+ 4 步依赖检查流程注释；单测确认 avahi/NM 被拦、wait-online/apport 放行 | ADR-14 / ISSUE-16 |
| ISSUE-25 | dry-run 产生空回滚记录，致重启前体检误报 | resolved | `03-perf-tune.sh` 的 `--dry-run` 仍无条件 `: > disabled-units-<ID>.tsv` 建 0 字节文件；`preboot-check.sh` 用 `ls\|tail -1` 抓到它，`grep -vqE` 对空文件返回假 → 误判「禁用列表包含启动关键单元」（23/0/1） | dry-run 改写 `/dev/null`；体检改取**最新非空** tsv 并显式判空；删两份空文件。复验 24/0/0 与 49/0 | ADR-23 |
| ISSUE-26 | 新装 GNOME 扩展在当前会话不可用 | 现象：`gnome-extensions enable` 报「扩展不存在」；`gsettings --schemadir` 报「未知命令」 | Shell 缓存会话启动时的扩展列表；本机 glib 不接受该参数位置 | 直接写 `enabled-extensions` + `GSETTINGS_SCHEMA_DIR` 环境变量；注销重登生效。已写入 docs/13 §6 | ADR-24 |
| ISSUE-27 | Chromium 点击无反应、无法更新 | resolved | ① 11-05 20:42 崩溃留下 `SingletonLock`，指向的 PID 49363 已死；② 缺 zenity/kdialog/xmessage，Chromium 无法弹「资料被占用」对话框 → 静默退出；③ 应用占用导致 `snap refresh` 失败 | 删 3 个 Singleton 锁；snap 已刷新 3569→3580；`timeout 25 chromium` 持续运行（rc=124 为 timeout 所致）。排查手册见 docs/99 §2.9 | — |
| ISSUE-28 | 9 个脚本丢失可执行位，README 的 `./scripts/xxx.sh` 全部报「权限不够」 | resolved | 权限由 `-rwxrwxr-x` 退化为 `-rw-rw-r--`（内容未变，非语法问题）；01~06、99、bench、preboot、rescue、rollback 受影响 | `chmod +x scripts/*.sh` 全量修复，逐项复查仅剩 `^-rwx`；复验 `./scripts/99-verify.sh` 49/0 | — |
| ISSUE-29 | `systemctl restart upower` 后 `BAT0` 从 sysfs 消失，upower 不再显示电池 | resolved | 本机 `thinkpad_acpi` 在充电阈值（75/80）附近高频重注册电池（本次启动 169 次）；upower 重启与该重注册竞争，导致 `power_supply` 节点未重新挂载。ACPI 设备 `PNP0C0A:00` 仍在，不是硬件问题 | `udevadm trigger --subsystem-match=power_supply` 无效；`modprobe -r thinkpad_acpi && modprobe thinkpad_acpi` 后 BAT0 立即恢复（64%、健康 100%、阈值 75/80 全部保留）。已在 `13-battery-alert.sh` 封装 `restart_upower_safe()`：重启后检测 `BAT*`，缺失则自动重载模块 | ADR-29 |
| ISSUE-30 | 修改 kimpanel 扩展后 `fcitx5.service` 变 inactive，但仍有 fcitx5 进程 | resolved | Shell 重载 kimpanel 时触发 fcitx5 的 `--replace`：systemd 托管的旧实例以 status=0 正常退出，新实例被 GNOME Shell 派生（PPID=gnome-shell），systemd 侧因此显示 `inactive (dead)`，下次登录会再起一个造成双实例 | `kill` 派生实例后 `systemctl --user restart fcitx5.service`，进程 PPID 回到 `systemd --user`；`99-verify` 输入法段复验 5/5。教训：改 kimpanel 代码或重载扩展后，必须检查 `systemctl --user is-active fcitx5.service` | ADR-31 |
| ISSUE-31 | 快捷设置「键盘」项点开无响应，日志报 `error writing brightness 2` | resolved | 报错里的 2 是**键盘背光档位**（`max_brightness=2`），不是屏幕亮度。upowerd 缓存的 `/sys/class/leds/tpacpi::kbd_backlight/brightness` 句柄在挂起/恢复后失效：`KbdBacklight.GetBrightness` 报 `error reading brightness`，但 `GetMaxBrightness` 正常、手动 `tee` 写 sysfs 成功，证明驱动无问题，是 upower 层句柄失效 | `sudo systemctl restart upower` 后 Set/Get 往返正常（1↔2），BAT0 未丢失，Shell 报错归零。已加系统级自愈 hook `/etc/systemd/system-sleep/50-suona-upower`（`scripts/17-sleep-hook.sh`）：resume 后先读 KbdBacklight，只在失效时才重启 upower，并在 `BAT*` 缺失时自动重载 `thinkpad_acpi` | ADR-29 |
| ISSUE-32 | WorkBuddy 无法启动（点图标无反应/闪退） | resolved | `/opt/WorkBuddy/chrome-sandbox` 权限为 `0755`，**缺 setuid 位**（Electron 要求 `4755 root:root`）。同时 Ubuntu 默认 `kernel.apparmor_restrict_unprivileged_userns=1` 封掉了非特权 userns 沙箱，两条路都不可用，Chromium 内核直接 `FATAL: The SUID sandbox helper binary was found, but is not configured correctly` 退出 | `sudo chmod 4755 /opt/WorkBuddy/chrome-sandbox` 后启动正常（11 进程，无 FATAL，仅无害的 `GetVSyncParametersIfAvailable` 警告）。`dpkg --verify workbuddy` 无差异，说明包内容完好、只是权限位丢失（`dpkg --verify` 不校验权限）。**同批排查发现 `/opt/baidunetdisk/chrome-sandbox` 也是 0755**，已一并修复；`/opt/黑胶音乐` 原本就正确。已在 `99-verify.sh` 增加「Electron 沙箱」段，遍历 `/opt/*/chrome-sandbox` 断言 4755 | — |

## 排查原则
先看只读诊断再下结论，不用连续猜测代替测量；「配置写了」不等于「进程加载了」；
性能判断必须有纯用户态基准（bench.sh），排除主题/字体因素。
