# 07 · 架构决策记录 (ADR)

不修改旧结论；变更时新增 ADR 并在旧条目标注「被 ADR-xx 取代」。

## ADR-01 改动尺度 = 标准
允许 sysctl / 服务禁用 / 内核参数，每步 `backup_file` 并登记 `changes.tsv`，提供 rollback 与 rescue。
后果：需保留 `backup/`，不能随意清理。

## ADR-02 工程结构
> 路径已于 2026-11-05 更新为 `~/CodeBuddy/work/linux-tune_SuonaOS/`（见 ADR-12）；
> 原文记述的路径 `~/CodeBuddy/work/linux-tune/` 为改名前的历史值。

项目落 `~/CodeBuddy/work/linux-tune_SuonaOS/`，分 docs/scripts/dotfiles/vendor/baseline/backup/logs；
脚本幂等，dotfiles 软链指向项目内源文件。后果：改配置改 `dotfiles/`，不改 `~` 下软链。

## ADR-03 双系统保留 GRUB 超时 5s（取代 1s）
背景：原计划 5s→1s 省 4 秒，update-grub 时发现 Windows Boot Manager 与 recovery mode。
结论：保持 5s，preboot-check 增加双系统感知。后果：牺牲约 4s 换可用恢复入口。

## ADR-04 输入法自启改 systemd 用户服务
背景：.desktop 自启多次失败；im-launch 在 Wayland 分支不启动守护进程。
选项：修 .desktop / 复制包自带 desktop / systemd user unit。
结论：`~/.config/systemd/user/fcitx5.service`，Type=simple + ExecStart=/usr/bin/fcitx5 +
Restart=on-failure，挂 graphical-session.target；移除旧 autostart。
后果：自启可靠；改主题须 `systemctl --user restart fcitx5.service`，`fcitx5-remote -r` 不足。

## ADR-05 候选框主题优先于 Kimpanel
背景：Kimpanel 接管绘制后 classicui 主题/字体/圆角全失效（黑底灰框）。
结论：保留扩展安装状态，fcitx5 侧 `[Behavior/DisabledAddons]` 禁 kimpanel；
classicui.conf 显式 `UseDarkTheme=False` 防 prefer-dark 回落 default-dark。
后果：普通应用主题生效，GNOME 活动搜索框受限。二者在 GNOME Wayland 下互斥，无折中。

## ADR-06 诊断通知静音而非安装扩展
该通知只影响活动搜索框；通过禁用 notifications addon 或 GNOME 应用通知屏蔽处理。
后果：fcitx5 不再发桌面通知，输入功能不受影响。

## ADR-07 桌面主题与字体回退
用户偏好系统自带 Dock；卡顿排查期间回退主题、字体、Dock、输入法环境变量。
保留脚本可重跑，需求标记 cancelled/reverted。后果：99-verify 需适配（ISSUE-07）。

## ADR-08 执行模式：AI 生成命令，用户手动执行
用户要求「之后所有的代码操作都是你生成代码，我自己在终端输入」。
结论：AI 不调用执行/写文件工具，只输出可直接复制的完整命令块，标注位置/sudo/幂等/预期输出；
需判断时给只读回显命令，由用户贴回输出。heredoc 一律 `<<'EOF'` 防 `$` 展开。
后果：可审计、避免误操作；命令块必须一次可粘贴完，避免拆分多块造成漏执行（ISSUE-13）。

## ADR-09 上游立项报告作为外部输入
背景：存在 2026-09-10《SuonaOS 正式立项报告 v1.0》，与本项目为上下游关系。
结论：报告只读引用，差异登记 `spec/00-upstream.md`；本项目 spec 保持独立编号与状态，
不把商业排期强加为技术任务。后果：报告修订时人工同步差异表，技术结论可回填风险章节。

## ADR-10 「代码操作」与「文档编写」的边界（补充 ADR-08）
背景：ADR-08 规定「所有代码操作由 AI 生成命令、用户手动执行」，但用户随后要求
「建立 spec 文档」「根据立项文件编写 spec 计划」，并指出只给命令块未落盘等于没做。
结论：
- **系统变更类**（apt / systemctl / gsettings / 写 `/etc` / 改用户配置）→ 只输出命令块，用户执行。
- **项目内文档类**（`spec/` 与 `docs/` 的创建、修订）→ AI 直接落盘，因为用户要的是成品文件，不是命令。
- 判断标准：改动是否影响运行环境。影响 → 给命令；仅产出文本 → 直接写。
后果：文档即时可用，避免再次出现 ISSUE-13；系统配置仍完全由用户掌控。

## ADR-11 音频设备自动切换：清理 WirePlumber 状态而非装包
背景：蓝牙耳机（EDIFIER FitC）连接后不自动播放。`wpctl status` 显示 A2DP sink 已创建，
但默认输出仍是内置扬声器、Chromium 流仍绑在 ALC257；`~/.local/state/wireplumber/default-nodes`
残留 `default.configured.audio.sink=alsa_output...Speaker__sink`（手动固定过的默认值）。
选项：装 `pulseaudio-utils` 手工切 / 改 GNOME 设置 / 清状态 + 启用自动切换模块。
结论：
1. 备份后删除 `default.configured.audio.sink` 锁定项，让 WirePlumber 回到自动选择；
2. 在 `~/.config/pipewire/pipewire-pulse.conf.d/99-switch-on-connect.conf` 加载
   `module-switch-on-connect`，由它同时处理默认设备切换与已有流迁移；
3. `pulseaudio-utils`（提供 `pactl`）仅作为可选诊断工具，不是修复依赖。
后果：断连重连无需人工干预；`pactl` 缺失曾导致首轮诊断全为空输出（错误被 `2>/dev/null` 吞掉），
故后续音频排查统一先用 `wpctl` / `pw-dump` 验证工具存在性。

## ADR-12 项目目录改名与绝对路径约束
背景：项目目录由 `linux-tune` 改为 `linux-tune_SuonaOS`，立项报告 HTML 移入 `spec/`。
结论：保留改名；但 dotfiles 采用绝对路径软链，改名后 `~/.zshrc` / `~/.tmux.conf` /
`~/.vimrc` / `~/.config/starship.toml` 全部断裂，需重跑 `04-devtools.sh` 重链。
约束：今后不得再改项目目录名；若必须改名，先执行「软链清单 + 文档路径批量替换」。
`scripts/lib/common.sh` 用 `$(dirname BASH_SOURCE)/..` 动态计算 `PROJECT_ROOT`，不受改名影响。
后果：脚本可继续工作，但用户级配置与 `RECOVERY.txt`、`docs/` 中的绝对路径需同步（ISSUE-15）。

## ADR-13 手机互联工具选型（GSConnect 为主，scrcpy / LocalSend 为辅）
> **已被 ADR-15 取代（2026-11-05）**：用户要求手机端零安装，本 ADR 的选型不再适用。
> 保留原文以记录决策演变；实际执行以 ADR-15 与 `docs/11-手机互联.md` 为准。

背景：需要在本机与手机间实现通知、剪贴板、文件互传、投屏、远程输入。
选项：
- **GSConnect**（GNOME Shell 扩展，实现 KDE Connect 协议）— 与 GNOME 顶栏/快速设置集成最深，无需常驻 KDE 应用；
- KDE Connect 桌面应用 — 功能等同但 GNOME 集成弱，且官方说明与 GSConnect 不可并存；
- scrcpy + adb — 只解决 USB/Wi-Fi 投屏与控制，不解决通知/剪贴板；
- LocalSend — 只解决文件互传，跨平台（含非 Android）且无需配对；
- Syncthing — 长期目录同步，非即时互联。
结论：**GSConnect 为主 + scrcpy/adb 为投屏补充 + LocalSend 为文件互传补充**，不安装 KDE Connect 桌面应用。
已知缺陷：Ubuntu 26.04 源内 GSConnect 71 在 GNOME Shell 50 剪贴板插件挂起（Launchpad
Bug #2172008，需 v74）。Phase 1 接受局部降级；若必须剪贴板，从 extensions.gnome.org
下载 v74+ 用 `gnome-extensions install --force`，但需自行承担版本校验风险。
后果：主体功能可用、剪贴板待处理（ISSUE-17）；KDE Connect 协议端口 1714–1764 需在 ufw 启用时放行。

## ADR-14 恢复 avahi-daemon，并建立服务精简白名单
背景：阶段 2 按「桌面机冗余」禁用了 21 个单元，其中包含 `avahi-daemon.service` 与 `.socket`。
手机互联依赖 mDNS/DNS-SD 发现设备，禁用后 GSConnect / LocalSend 无法在同一 Wi-Fi 内发现对端。
结论：
1. `avahi-daemon` 恢复启用，标记为**禁止精简白名单**；
2. 涉及网络发现、打印、蓝牙、音频的服务今后禁用前先查依赖；
3. `03-perf-tune.sh` 的禁用清单需补充注释说明例外，回滚记录仍保留。
后果：`03-perf-tune.sh` 若被重跑会再次禁用 avahi —— 必须先修脚本，否则问题复发（ISSUE-18）。
这暴露出结构性缺陷：批量服务精简缺少「功能依赖检查」，后续新增功能前应先查 `disabled-units-*.tsv`。

## ADR-15 手机端零安装 → 改用 ADB-only 方案（取代 ADR-13 的选型）
背景：用户明确手机为红米（HyperOS / Android），且**不接受安装任何第三方 App**。
ADR-13 的 GSConnect / KDE Connect / LocalSend 全部要求手机端装应用，与约束直接冲突（ISSUE-19）。
选项：
- 放弃互联；
- 装手机端 App（违反约束）；
- **ADB 生态**：手机只用系统自带「开发者选项 → USB 调试 / 无线调试」，桌面用已装的
  `adb` + `scrcpy`。scrcpy 仅临时 push 一个 server 到 `/data/local/tmp`，不落地为应用。
结论：采用 ADB-only。能力映射：
| 能力 | 手段 |
|---|---|
| 投屏 + 反向控制 | `scrcpy` |
| 文件双向传输 | `adb push/pull`；scrcpy 拖文件到窗口 |
| 剪贴板 | `Ctrl+C` 取手机剪贴板 / `Ctrl+V` 推送到手机（scrcpy 内） |
| 免 USB 线 | HyperOS「无线调试」+ `adb pair` / `adb connect` |
| 通知同步 / 电量 / 寻响 | **放弃**（这些必须依赖手机端常驻 App） |
已装的 `gnome-shell-extension-gsconnect` 成为冗余，暂不卸载（可选精简 TASK-32），
但不再启用，也不影响 ADB 方案。
后果：零新增安装、零手机端侵入；代价是没有通知同步与后台自动同步。
adbd 仅在 USB 调试开启时暴露，用完建议关闭（见 `docs/11` 安全章节）。

## ADR-16 一键连接：记忆地址而非依赖 mDNS 自动发现
背景：用户不接受「每次连接都手输一长串命令」，而 HyperOS 无线调试端口会变。
实测 `adb mdns services` 返回空列表、`avahi-browse -rt _adb-tls-connect._tcp` 也无输出，
说明该机型不广播 ADB 服务，**mDNS 自动发现不可用**（此前为 GSConnect 恢复的 avahi 对此无效）。
选项：
- systemd user timer 定时轮询重连（常驻、耗电、侵入性强）；
- 固定 5555 端口（`adb tcpip 5555`，但手机重启后失效且部分机型需 USB 初始化）；
- **脚本记忆上次成功地址 + 端口变更时单次覆盖**。
结论：采用第三种，实现为 `scripts/mobile-connect.sh`：
无参数自动复用已连接设备或上次地址；端口变了执行 `mobile-connect.sh <端口>` 一次即记住；
`--tcpip` 作为可选的长期固定方案；`--status` / `--stop` 提供只读与收尾。
投屏参数（`--shortcut-mod=lctrl --max-size 1080 --max-fps 60 --stay-awake`）固化在脚本内。
桌面启动器与 shell 别名作为用户级便捷入口（命令块由用户执行，ADR-08）。
后果：日常零输入；端口变化时需从手机页面读一次端口号。
已确认 `navigation_mode=2`（全手势），投屏操作依赖 scrcpy 快捷键而非画面按钮（ISSUE-22）。

## ADR-17 投屏窗口尺寸按逻辑像素自适应
背景：`xrandr` 报物理 3072x1920，但 GNOME 200% 缩放，
Mutter `GetResources` 返回逻辑桌面 1536x960。用户反馈投屏窗口偏小（ISSUE-23）。
根因：`--max-size 1080` 限制的是视频宽和高都不超过 1080，对 1080x2400 竖屏
等于把高度压到 1080、宽度只剩 486；窗口默认跟随视频尺寸，于是成窄条。
结论：
1. 窗口尺寸与视频编码尺寸解耦 —— `--window-width/height` 显式指定窗口；
2. 默认高度 840 逻辑像素（960 减去顶栏与余量），宽度按 `wm size` 的视频比例算出；
3. `--max-size=1920` 仅限制编码分辨率以控制无线带宽，不再决定窗口大小；
4. 高度可用 `MC_HEIGHT` 环境变量临时覆盖，或写 `mobile.conf` 永久生效，建议 700~900。
后果：窗口占逻辑桌面高度约 87%；全屏 `-f` 对竖屏会产生大黑边，不推荐。
高分屏下所有窗口参数都应以逻辑像素为准，不能直接用 `xrandr` 的物理分辨率。

## ADR-18 桌面启动器作为一等资产，随脚本同步演进
背景：脚本新增窗口自适应、`MC_HEIGHT`、`--port-prompt` 后，启动器仍是旧版：
仅一条 Exec、无快捷操作、`Terminal=false` 会让端口变化时的提示**静默不可见**，
且缺 `StartupWMClass` 导致窗口图标无法关联。
结论：
1. 启动器模板纳入项目 `dotfiles/desktop/mobile-connect.desktop.template`，用
   `__PROJECT_ROOT__` 占位，安装时 sed 替换 —— 目录改名不再产生硬编码失效（ADR-12 教训）；
2. `Terminal=true`：让脚本的错误提示与交互输入可见（尤其是 `--port-prompt`）；
3. `StartupWMClass=scrcpy`（实测 WM_CLASS），`Icon=phone`（本机图标存在）；
4. 四个 Desktop Action：状态 / 断开 / 大窗口(900) / 端口已变化；
5. 脚本新增 `--port-prompt`，用 `exec "$0" "$PORT"` 复用端口分支，避免 case fallthrough 陷阱。
后果：启动器与脚本必须**一起改**；单独改脚本会留下功能缺口。
安装属用户级配置变更，按 ADR-08 只输出命令块由用户执行。

## ADR-19 检测脚本禁止静默降级：「读不到」不等于「不存在」
背景：`battery-check.sh` 用 `SUDO="sudo -n"; $SUDO true 2>/dev/null || SUDO=""`
在免密 sudo 失效时静默降级，`dmidecode -t 22` 输出为空，第 9 节据此判定
「固件未报告电池 → 物理无电池」（ISSUE-05）。用户复跑 `sudo dmidecode -t 22`
证明电池一直存在且健康 100.7%，整套「无电池」推断作废，连带
「无电池 + USB-C 导致 CPU 锁频」的因果结论也被推翻。
结论：
1. 所有只读检测脚本，权限不足必须**显式告警**并输出「无法判定」，禁止给出阴性结论；
2. 空输出、命令非零退出、工具缺失三者必须区分，不能统一当作「没有该设备」；
3. 阴性结论需**两个独立证据源**交叉验证（本次：DMI Type 22 + sysfs BAT0 + upower）；
4. 产品文档中的因果推断若建立在某个检测结论上，该结论被推翻时必须一并回溯更正。
后果：`battery-check.sh` 已改；`00-upstream`、`suonaos/02-technical-spec`、
`suonaos/05-acceptance-risks` 的 SR-12/A-07 均已更正。
CPU 锁频根因回归为 EC/SMU 状态异常（完整断电复位），与电池无关。

## ADR-20 范围裁剪：两项验证不再执行
背景：2026-11-05 项目剩 2 项 `in_progress`：TASK-01（确认 Wayland 诊断通知是否静音）、
TASK-29（验证 scrcpy 键鼠反向控制）。用户明确「剩余的 2 项不需要做了」。
结论：
1. TASK-01 / TASK-29 标记 `cancelled`，编号保留（编号只增不复用）；
2. REQ-11 静音诊断通知 → `cancelled`，ISSUE-03 → `closed`：**接受通知继续出现**，
   不再作为缺陷跟踪，也不再追问用户是否还弹；
3. REQ-20/21/22 手机互联 → `done`：连接、投屏画面、无线链路、一键启动器均已实测交付，
   未验证的反向控制/剪贴板不影响主体交付，不再补测；
4. TASK-03/09/10 原依赖 TASK-01，现解除依赖并保留为独立文档同步待办；
5. M3 完成度由 30% 调整为 60%，P0~P2 重新编排。
后果：`in_progress` 归零；剩余均为 `planned`（文档同步、体检脚本、性能复测）与
`deferred`（字体偏好、固定 5555 端口、卸载 GSConnect）。
若日后用户改变主意，应**新建 TASK** 而非复活已取消的编号。

## ADR-21 校验脚本必须状态感知，不硬编码单一期望值
背景：`99-verify.sh` 起初按「优化全部生效」写死断言（GRUB=1s、Inter、JetBrains、
WhiteSur 全套）。后续 ADR-03 因双系统保留 5s、ADR-07 回退字体/主题/Dock，
脚本未同步，长期报 4 项失败（ISSUE-07），**假失败掩盖真问题**。
结论：`99-verify.sh` 按可观测的当前状态分支，每条路径各自做正向断言而非跳过：
1. GRUB：检测 `grub.cfg` 是否含 Windows Boot Manager → 双系统断言 `>=3s`，单系统断言 `1s`；
2. 字体：按 `font-name` 是否含 Inter → 定制态校验 Inter/JetBrains/fontconfig 存在，
   回退态校验「非 Inter」「非 JetBrains」「fontconfig 已清理」；
3. 主题：按 `gtk-theme` 是否含 WhiteSur → 定制态保留原 8 项，回退态改为
   「非 WhiteSur」「图标非 WhiteSur」「无自定义 Shell 主题」3 项正向断言。
校验项随分支增减（回退态 45 项），**不追求固定总数**；任何配置下都必须是真检查，
不允许用 `val` 跳过或恒真断言凑零失败。
后果：回退态 45/45、定制态 mock 45/45 均零失败；恢复任一方案无需改脚本。
今后新增会回退/取消的优化，必须同时写两套断言，否则不许标记 `done`。

## ADR-22 项目改名后的路径判定：区分「项目根路径」与「配置名」
背景：目录从 `linux-tune` 改名为 `linux-tune_SuonaOS`（ADR-12）后，全库仍有 20+ 处
`linux-tune` 字面。若一律 sed 替换，会改坏仍在生效的配置；若一律保留，
急救文档里的 `cd ~/CodeBuddy/work/linux-tune` 在启动失败时指向不存在的目录。
结论——按**是否指向项目目录**分三类处理：

| 类别 | 例子 | 处理 |
|---|---|---|
| 项目根路径 | `~/CodeBuddy/work/linux-tune`、`docs/04` 软链示意、目录树根部、README 的 `cd` | **必须改**为 `linux-tune_SuonaOS` |
| 生效中的配置名 | `/etc/sysctl.d/99-linux-tune.conf`、`~/.config/linux-tune/mobile.conf` | **保持不动**，改名会破坏脚本/系统配置 |
| 生成标记 / 历史记述 | `# 由 linux-tune 生成`、ADR-02 里标注的旧值 | **保持不动**，只是署名或史料 |

已修范围：`RECOVERY.txt`、`docs/98`、`docs/99`、`docs/04`、`docs/01`、
`README.md`、`scripts/rescue.sh`、`spec/suonaos/06-milestone-audit.md`。

验证方式（**必须排除 ADR-02 的历史记述与本 ADR 自身的正则**，否则永远 2 命中）：

```bash
# 期望输出 0 行
grep -rn 'work/linux-tune$\|work/linux-tune/' \
     docs/ scripts/ README.md spec/ 2>/dev/null \
  | grep -v '07-decisions.md'
```

另需 4 个 dotfiles 软链全部有效、`bash -n` 全部通过。
已知有意保留：`spec/07-decisions.md` 内的 2 处（ADR-02 原文记述 + 本 ADR 的正则）。
后果：REQ-19 由 `in_progress` 收口为 `done`。今后再次改名，按此表分类替换，
**不要用无差别全局替换**。

## ADR-23 dry-run 必须真正只读，且快照选择要跳过空文件
背景：为验证服务白名单跑了 `03-perf-tune.sh --dry-run`，脚本却无条件
`: > logs/disabled-units-<RUN_ID>.tsv` 生成两份 0 字节记录。
`preboot-check.sh` 用 `ls | tail -1` 取到空文件，加上 `grep -vqE` 对空输入返回假，
误报「禁用列表包含启动关键单元」，体检从 24/0/0 变成 23/0/1。
更危险的是 `rollback.sh` 按批次取文件，空记录会让「恢复 21 个服务」静默变成空操作。
结论：
1. **dry-run 不得写任何真实状态文件**：`UNIT_STATE=/dev/null`，只有正式执行才建 tsv；
2. **选择历史快照必须过滤空文件**：按修改时间倒序取第一个 `-s` 为真的，
   找不到时显式 `warn`，不要用 `grep -vqE` 这种对空输入语义反直觉的写法；
3. 回滚类数据文件是安全资产，宁可报「找不到」，不可静默当成「空清单」。
后果：已删两份空文件，真实 21 行记录完好；两套体检恢复 24/0/0 与 45/0。
原则适用于本项目的 `backup/`、`baseline/`、`logs/` 下所有按时间取最新快照的逻辑。

## ADR-24 美化分三层：GRUB 用主题包、Dock 用原生、顶栏才用扩展
背景：2026-11-06 用户要求「GRUB 美化 + Dock 和工具栏透明度」。此前桌面主题
曾按 ADR-07 整体回退，这次是**新增独立需求**，不代表恢复 WhiteSur 全套。
结论：
1. **GRUB**：用 `vinceliuice/grub2-themes` 的 Vimix（`-s 2k -i white`），
   装到 `/usr/share/grub/themes/`（不是 `/boot/grub/themes`，避免 /boot 空间与
   initramfs 耦合）；`GRUB_TIMEOUT=5` **不动**（ADR-03 双系统）。
2. **Dock**：用 `dash-to-dock` 原生 `transparency-mode=FIXED` + `background-opacity`，
   **不引入扩展**——零依赖、即时生效、无会话风险。
3. **顶栏**：GNOME 没有顶栏透明度的 gsettings 键，只能靠扩展接管背景绘制。
   选 Blur my Shell（`blur-my-shell@aunetx`，metadata 明确支持 48~51），
   必须同时开 `override-background=true`，否则模糊只是叠在不透明黑底上。
4. 扩展配置用 `GSETTINGS_SCHEMA_DIR` 环境变量；本机 glib **不接受**
   `gsettings --schemadir`（报「未知命令」）。
5. 新装扩展在当前会话不可用（Shell 缓存扩展列表），直接写
   `org.gnome.shell enabled-extensions`，注销重登后加载。
后果：REQ-23/24 标 `done`；`99-verify.sh` 新增「美化」段 3 项（45→48）；
GRUB 视觉效果待重启、顶栏待重登确认，二者都不影响当前可用性。
回滚：`backup/20261106-075444/`（grub + grub.cfg）；Dock/扩展见 `docs/13` §5。

## ADR-25 壁纸：Commons 取图 + XML 时间轴，不用常驻脚本
背景：2026-11-06 用户要求「桌面背景增加一些水系主题图片」。
选项：AI 生成 / Unsplash / Pexels / Wikimedia Commons / 用户自备。
结论：
1. **来源**：Wikimedia Commons API（无需密钥、授权字段可查）。Unsplash 搜索页反爬
   （返回 9 KB 空壳）、`napi` 要 Authorization、`source.unsplash.com` 已停用；Pexels
   页面同样被拦。Commons 的 `thumburl` 可直接取 3840 宽原图。
2. **授权**：CC BY / CC BY-SA / FAL **免费可商用但要求署名**，因此必须生成
   `CREDITS.txt`（作者 + 授权 + 来源链接）。对外分发含壁纸的截图也要保留。
3. **轮换**：GNOME 只认 XML 时间轴（`<static>` + `<transition>`），
   不支持「指定文件夹自动轮换」。因此**不写常驻守护进程**，只生成 XML 并
   把 `picture-uri` 指过去，零后台开销、注销重启后依然有效。
4. **规格**：统一裁切 3072×1920（本机原生），`picture-options=zoom`；
   原图保留在 `water/` 下便于重新裁切。
后果：REQ-25 标 `done`；`99-verify.sh` 美化段新增壁纸检查（48→49）；
图片素材不入 git（体积大、授权独立），只入脚本与署名清单。
回滚：`gsettings reset picture-uri` / `picture-uri-dark`，图片可保留。

## ADR-26 三项 deferred 收口：字体保持默认、GSConnect 卸载、5555 暂挂
背景：ADR-20 把 TASK-08 / TASK-32 / TASK-36 归入 `deferred` 等用户决定；
2026-11-07 用户要求「P2 落地」，逐项处置。
结论：
1. **字体（TASK-08）**：维持系统默认 `Adwaita Sans 11` / `Ubuntu Sans Mono 11`，
   不恢复 Inter / JetBrains Mono。ADR-07 的偏好（要系统自带外观）未变，
   这是**确认**而非新增回退。`fonts-inter`、`fonts-jetbrains-mono`、
   `~/.config/fontconfig/fonts.conf` 全部保留，想换回只需重跑 `./scripts/05-cjk-fonts.sh`
   （脚本第 3 步会重设 4 项 gsettings）。注意 GNOME 50 的默认族名已由
   `Adwaita Sans` 取代旧 `Cantarell`，断言不能写死。
2. **GSConnect（TASK-32）**：它是 **apt 包**（`gnome-shell-extension-gsconnect` v71，
   装在 `/usr/share/gnome-shell/extensions/`），不是用户目录扩展，因此用
   `apt purge` 卸载而不是删目录。**不执行 `apt autoremove`**：apt 会连带建议移除
   16 个「不再需要」的包（folks / edataserver / sshfs / python3-nautilus 等），
   它们可能被其他用途依赖，收益（1.6 MB）远小于风险。
3. **5555 固定端口（TASK-36）**：复测 `192.168.31.196:39959` 返回
   `Connection refused`，手机端无线调试已关闭或 IP 变更。该项依赖物理设备，
   标 `blocked`，待手机在线后执行 `./scripts/mobile-connect.sh --tcpip`。
后果：`deferred` 归零（TASK-08/32 → `done`，TASK-36 → `blocked`）。
`gnome-extensions list` 在卸载后**仍会列出** `gsconnect@andyholmes.github.io`：
该命令经 D-Bus 向运行中的 Shell 取列表，属会话缓存，与 ISSUE-26 同源；
包与目录已确认为空，注销重登即消失，**不是卸载失败**。
回滚：`sudo apt install gnome-shell-extension-gsconnect`；字体重跑 `05-cjk-fonts.sh`。

## ADR-27 声音主题：本地合成而非采样，只覆盖交互事件
背景：2026-11-08 用户要求「做一套声音主题，符合项目风格，尽量采用开源项目」。
选项：① 下载 CC0/CC-BY 音效包（Kenney / freesound）；② 采样真实唢呐；
③ ffmpeg `aevalsrc` 数学合成。
结论：
1. **选合成**。零第三方素材 ⇒ 无授权链、无 `CREDITS.txt` 维护、换机重装无需再取素材；
   产物体积 252 KB，`git` 里只存脚本，改音色等于改事件表一行。
2. **四族音色**：`wood` 木腔 / `porcelain` 瓷击 / `reed` 哨片 / `lowwood` 低木，
   对应唢呐的木质管身与簧片。「唢呐感」只保留在 `reed` 族（5.5Hz 颤音 + 起振），
   且**不用于高频事件**——日常的消息/音量走木腔与瓷击，避免长期听觉疲劳
   （与 ADR-07「不要浮夸外观」同一取向）。
3. **只覆盖 26 个交互事件**：`audio-channel-*`（10 个）与 `audio-test-signal` 不覆盖，
   回落到 freedesktop。调试音不是产品音效，覆盖反而增加维护面。
4. **峰值归一化**，不按波形系数估算响度：渲染 `pcm_s16le` → `volumedetect` 读峰值 →
   `volume=<dB>` → **一次性**编码 Vorbis q5（避免二次压缩）。默认目标 −3.5 dBFS；
   例外：`audio-volume-change` −9（跟手刻度音）、`camera-shutter` −4 / `screen-capture` −7
   （瞬态强）、`dialog-error`/`suspend-error` −2.5（需要被注意到）。
   初版按系数估算时 reed 族只有 −19 dB、快门 −0.5 dB，实测后才改为归一化。
5. **装到用户级** `~/.local/share/sounds/Suona/`，不写 `/usr/share`：回滚只需
   `gsettings` 复原 + `rm -rf`，不触碰系统目录（同 ADR-07 的边界）。
后果：REQ-26 / TASK-43 `done`；`99-verify.sh` 新增「声音主题」段 4 项（49 → 53），
按 ADR-21 做状态感知（定制态断言 4 项，默认态只断言「非 Suona」）。
验证：`strace -f -e trace=openat canberra-gtk-play -i bell` 实际打开
`~/.local/share/sounds/Suona/stereo/bell.oga`，证明 libcanberra 未回落 freedesktop。
回滚：`./scripts/11-sound-theme.sh --restore`。

## ADR-28 系统音效与应用音量：在生成端衰减，不用 WirePlumber 规则
背景：2026-11-08 用户要求「修复可能存在的系统声音和各应用之间的音量不匹配」。
诊断：
1. GNOME 50 的 `org.gnome.desktop.sound` 只有 4 个键
   （`theme-name` / `event-sounds` / `input-feedback-sounds` / `allow-volume-above-100-percent`），
   **没有系统音效音量**。
2. libcanberra 的流带 `media.role=event`、`module-stream-restore.id=sink-input-by-media-role:event`，
   与应用共享同一个 sink 音量。
3. 应用内容约 −14 LUFS（峰值 −1 dBFS），首版提示音峰值 −3.5 dBFS，差 2.5 dB
   ⇒ 短促提示音压过音乐/会议。
选项：A 用 WirePlumber `stream.rules` 给 event 流设 `target.volume`；
B 在生成端统一衰减（`SYS_DECAY_DB`）。
结论：**选 B，A 已被实测否证**：
- 写入 `~/.config/wireplumber/wireplumber.conf.d/51-suona-event-volume.conf`
  并重启 WirePlumber，服务 `active`、日志无报错，但 `pactl list sink-inputs`
  显示 event 流仍为 `65536 / 100% / 0.00 dB`，`stream-properties` 无 event 记录
  ⇒ 规则被加载，但 `update-props.target.volume` 对 client stream 不生效
  （pulse 层默认音量优先）。配置已删除，未留在系统。
- B 100% 可控、无系统风险、可重新生成；改变的是文件绝对峰值而非运行时增益，
  但音效与应用共享 sink 音量，比例关系不变，正是所需效果。
参数：`SYS_DECAY_DB` 默认 **−6.5 dB**，存 `~/.config/linux-tune/sound.conf`，
`--decay` 临时覆盖。最终峰值：默认 −10.0 dBFS、错误 −9.0、快门 −10.5、
刻度音与截屏 −13.5。
后果：`99-verify.sh` 声音段 4 → 5 项（新增「峰值 ≤ −8 dBFS」裁决音量匹配），总 53 → 54。
回滚：`--decay -3.5` 回到原峰值；或 `--restore` 回默认主题。
副作用记录：排查期间两次重启 WirePlumber，蓝牙 sink 音量被 AVRCP 从 0.30 同步到 0.48，
已用 `wpctl set-volume 69 0.30` 还原；该抖动不写入交付镜像的默认值。

## ADR-29 电池提示只做关键节点，低电量复用 gsd-power 既有事件名
背景：用户反馈「电池电量变化会触发右上角图标变化并触发提示音」，要求
「在关键节点提示（20% / 10% / 充满），而非每次电量变化」。
实测否证「每次变化都响」：90 秒 `pactl subscribe` 音频流 0 个、
`udevadm monitor power_supply` 事件 0 个；upower 仅每 30 秒轮询（5 次 attributes 变更，
无声音）；169 次 `battery 1 registered` 集中在生成音效的高负载期，与音频无关。
结论：
1. **20% / 10% 不写守护进程**：`/usr/libexec/gsd-power` 内置
   `battery-low` / `battery-caution`（以及 `power-plug` / `power-unplug`）事件名，
   而 freedesktop 主题没有 `battery-*` 文件 ⇒ 低电量长期**静音**。补齐文件即自动触发，
   零常驻、零轮询。`strace` 证实命中 `Suona/stereo/battery-low.oga`。
2. **充满才自建**：gsd-power 无「充到上限」事件。引入
   `suona-battery-alert.timer`（60s oneshot），用 `charge_control_end_threshold`
   （本机 80%）而非 100% 判定——养护阈值下 `status` 变 `Not charging`，
   只看 `Full` 永不触发。
3. **去重三态**：state 文件 `空 / full-notified / idle`；拔电或放电即复位，
   保证「只响一次」。单测通过 `BAT_DIR` / `AC_ONLINE_FILE` 伪造 sysfs，
   实测 `full → 幂等 → idle`，不依赖真实放电耗时。
4. **阈值只改 Critical**：`PercentageLow` 默认已是 20.0，无需动；
   `PercentageCritical` 5.0 → 10.0（5% 对笔记本太晚）。改前 `backup_file`
   备份 `UPower.conf`，改后重启 upower。
5. **不做「每 1% 提示」**：那是每小时数十次事件，既吵又无信息量；
   图标本身已随电量变化（upower 轮询），无需声音重复表达。
后果：`99-verify.sh` 新增「电池提示」段 3 项，54 → 57；主题事件 26 → 29。
回滚：`./scripts/13-battery-alert.sh --restore`（停 timer + 恢复 UPower.conf 备份）。

## ADR-30 日落深色 + 圆角：用户级覆盖，不做 shell theme
背景：2026-11-08 用户要求「暗色样式随日落开关」「桌面及部分软件圆角优化」。
结论：
1. **日出日落本地算**（NOAA 简化算法，Python 标准库），不联网、不用 geoclue、
   不装第三方扩展。实测上海 11-08 得 06:15/17:01，与权威值一致。
2. **同时写两个键**：`color-scheme`（libadwaita/GTK4）与 `gtk-theme`
   （GTK3，`Yaru-prussiangreen(-dark)`）。只写一个会出现「一半应用不变色」。
3. **必须先拆掉旧的 dark 硬链**：`~/.config/gtk-4.0/gtk.css` 原是指向
   9424 行 `gtk-Dark.css` 的软链，导致 GTK4 应用**永远暗色**，`color-scheme`
   对它完全无效——日落切换会「看起来没生效」。已按本 ADR 移除并备份。
4. **圆角只做 GTK 外壳**：窗口 14px、弹层 14px、GTK3 `decoration` 外框。
   不动控件内部圆角（按钮/输入框/卡片需逐个对齐 Yaru 尺寸变量，收益小）。
   GNOME Shell 的弹窗/通知圆角需要自定义 shell theme，与 ADR-07「回系统默认外观」
   冲突，**不做**；Dock 没有圆角配置项，也不做。
5. 状态去重：`auto-dark.state` 记录上次模式，未跨日出日落不重复写 gsettings。
后果：REQ-28/29；`99-verify.sh` 新增「日光与圆角」段 3 项，57 → 60。
回滚：`14-auto-dark.sh --restore` / `15-rounding.sh --restore`。

## ADR-31 输入法图标：只打一处补丁，不动 fcitx5 配置
背景：用户指出顶栏输入法图标是彩色红色「拼」，与周围单色 symbolic 图标不一致。
根因：kimpanel 的 `createIcon()` 故意请求 `name + '-symbolic-hack'` 以绕过
GTK 单色化，最终命中 `fcitx-pinyin.png`（红色位图）。这不是主题问题，改
icon-theme 或候选框主题都没用。
选项：A 改 fcitx5 的 `pinyin.conf` 去掉 Icon；B 覆盖彩色 PNG 为单色位图；
C 提供 symbolic 图标 + 扩展补丁。
结论：**选 C**。
- A 的 `pinyin.conf` 在 `/usr/share/fcitx5`，改系统文件且可能被升级覆盖，
  且去掉 Icon 后会退回纯文字标签，丢失「输入法状态」的图形表达。
- B 的 PNG 固定颜色，深色顶栏下会看不见，且位图不跟随主题着色。
- C 只在用户级加一个 SVG（复用 Adwaita `input-keyboard-symbolic`），
  再给 kimpanel 加 `createSymbolicIcon()`，把顶栏主图标改成请求 `-symbolic`；
  菜单项仍走原 `createIcon` 保持彩色。找不到 symbolic 时 GTK 自动回落到
  原彩色图标，不会变空。
代价：**修改了第三方扩展**，升级会覆盖。因此补丁做成幂等脚本
`16-ime-icon.sh --install`，并在 `--status` 里显式报告三项是否就位。
生效需注销重登（Wayland 下 Alt+F2 → r 不可用）。
回滚：`16-ime-icon.sh --restore`（反向替换 + 删除用户图标）。

## ADR-32 Shell 圆角用「叠加式」用户主题，不与 ADR-07 冲突
背景：用户追问「桌面和部分软件可以圆角么」。GNOME Shell 的菜单/通知/OSD/Dock
圆角只能由 shell theme 控制，GTK CSS 管不到；而 ADR-07 曾把自定义 shell 主题
整体回退。若直接恢复 WhiteSur 就等于推翻 ADR-07。
结论：
1. 新建 `~/.themes/Suona-Round/gnome-shell/gnome-shell.css`，内容只有
   `@import url("file:///usr/share/themes/Yaru/gnome-shell/gnome-shell.css")`
   + 5 条圆角规则（菜单 / 快捷设置 / 通知 / OSD / Dock 背景）。
   配色、布局、图标全部继承 Yaru，**不是**换主题。
2. 用 `user-theme` 扩展激活，**即时生效**（WhiteSur 那会儿需要重登，
   这里只改 CSS 属性，扩展会热加载）。
3. `99-verify.sh` 的主题段从「二态」改成**三态断言**：
   无 shell 主题 / `Suona-*` 仅圆角覆盖 / 其他自定义主题，各自正向断言。
   否则启用圆角会被误判成「恢复浮夸外观」而报红。
4. 复制整份 shell CSS 的做法被否决：Yaru 的 `gnome-shell.css` 有 319 KB，
   复制会产生升级后过时的副本；`@import` 跟随系统更新，且实测加载无报错
   （`gnome-shell: loading user theme` 正常打印）。
后果：REQ-29 的覆盖范围扩展到 Shell 与 Dock；体检仍 60 项零失败。
回滚：`15-rounding.sh --restore` 或 `gsettings set org.gnome.shell.extensions.user-theme name ''`。
遗留：`~/.themes/WhiteSur-*` 共 100+ 个目录（ADR-07 回退后未删）仍占空间，
另有 `~/.icons`、`~/.local/share/gnome-shell/extensions` 的残留，列为后续清理项。
