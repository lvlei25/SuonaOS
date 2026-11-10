# Linux 系统优化项目

面向 **Ubuntu 26.04 LTS + GNOME 50 (Wayland)** 的笔记本系统调优与主题美化工程。
所有改动均脚本化、可备份、可回滚，并沉淀为可复用文档。

## 目标机器

| 项目 | 配置 |
|---|---|
| 机型 | ThinkPad T14 Gen 5 (21MCCTO1WW) |
| CPU | AMD Ryzen 5 PRO 8540U（6C/12T，最高 4.98GHz） |
| 显卡 | Radeon 740M（RDNA3 集显） |
| 内存 | 13 GiB 可用 |
| 磁盘 | KIOXIA NVMe 512G，283G ext4 根分区 |
| 系统 | Ubuntu 26.04.1 LTS (resolute)，内核 7.0.0-42 |
| 桌面 | GNOME Shell 50.1 / Wayland |

## 优化方向（已确认）

| 阶段 | 内容 | 脚本 | 状态 |
|---|---|---|---|
| 0 | 基线快照与环境部署 | `scripts/00-preflight.sh`、`scripts/01-install-base.sh` | ✅ |
| 1 | 网络加速（apt / pip / npm / GitHub） | `scripts/02-network-mirrors.sh` | ✅ |
| 2 | 性能优化（zram / sysctl / 服务精简 / 启动） | `scripts/03-perf-tune.sh` | ✅ |
| 3 | 开发环境（zsh / tmux / vim / node / uv） | `scripts/04-devtools.sh` | ✅ |
| 4 | 中文与字体渲染 | `scripts/05-cjk-fonts.sh` | ✅ |
| 5 | WhiteSur 主题美化 | `scripts/06-theme-whitesur.sh` | ✅ |
| 6 | 输入法 fcitx5 接管 | `scripts/07-ime-fcitx5.sh` | ✅ |
| 7 | 输入法美化（候选框主题） | `scripts/08-ime-theme.sh` | ✅ |
| 8 | 验证与回滚 | `scripts/99-verify.sh`、`scripts/rollback.sh` | ✅ |
| 9 | 声音主题（Suona 提示音） | `scripts/11-sound-theme.sh` | ✅ |
| 10 | 电池关键节点提示 | `scripts/13-battery-alert.sh` | ✅ |
| 11 | 日落自动深色 | `scripts/14-auto-dark.sh` | ✅ |
| 12 | GTK 圆角覆盖层 | `scripts/15-rounding.sh` | ✅ |
| 13 | 输入法顶栏图标单色化 | `scripts/16-ime-icon.sh` | ✅ |

改动尺度：**标准**（允许 sysctl / 服务调整，每步备份 + 一键回滚）。

## 目录结构

```
linux-tune_SuonaOS/
├── README.md              项目总览（本文件）
├── docs/                  可复用文档
│   ├── 00-基线快照.md      优化前状态与瓶颈分析
│   ├── 01-环境部署.md      工具链、目录规范、sudo 与备份机制
│   ├── 02-网络加速.md
│   ├── 03-性能优化.md
│   ├── 04-开发环境.md
│   ├── 05-中文与字体.md
│   ├── 06-主题美化.md
│   ├── 07-输入法.md
│   ├── 08-输入法美化.md    fcitx5 候选框主题（66 套）
│   ├── 11-手机互联.md      ADB-only 投屏与文件互传
│   ├── 12-交付报告.md      M5 归档：成效、清单、取舍、复用步骤
│   ├── 13-GRUB与透明度美化.md  GRUB Vimix + Dock/顶栏透明
│   ├── 14-桌面壁纸.md      水系壁纸轮换与素材授权
│   ├── 15-声音主题.md      Suona 提示音主题（ffmpeg 合成，29 事件）
│   ├── 16-电池提示.md      20%/10%/充满三节点提示与 upower 阈值
│   ├── 17-界面细节优化.md  日落深色 / 圆角 / 输入法图标
│   ├── 98-启动恢复.md      四级启动失败恢复流程
│   └── 99-故障排查.md
├── scripts/               所有可执行脚本
│   ├── lib/common.sh      公共函数（日志/备份/apt 封装）
│   └── ...
├── dotfiles/              配置源文件（软链到 $HOME）
│   ├── zsh/.zshrc
│   ├── tmux/.tmux.conf
│   ├── vim/.vimrc
│   └── starship.toml
├── vendor/                主题源码缓存（可离线重装）
├── baseline/              每次基线采集的快照（只读）
├── backup/<时间戳>/        被修改文件的原始副本
└── logs/                  运行日志 + changes.tsv 变更登记表
```

## 执行结果

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 可用交换 | 4.0 GiB（磁盘） | 10.9 GiB（4G 磁盘 + 6.9G zram/zstd） |
| `vm.swappiness` | 60 | 10 |
| 拥塞控制 | cubic | bbr |
| crashkernel 预留 | 512 MiB | 0 |
| 运行中服务 | 36 | 约 25（21 个单元已禁用） |
| 开机 userspace | 11.122s | 约 4~5s（重启后确认） |
| 开机总计 | 26.408s | 约 18~19s（重启后确认） |
| 界面字体 | Adwaita Sans 11 | Inter 11 |
| 等宽字体 | Ubuntu Sans Mono 11 | JetBrains Mono 11 |
| 主题 | Yaru-prussiangreen | WhiteSur-Dark（含 Shell/图标/光标） |
| 输入法 | ibus（fcitx5 装了未用） | fcitx5（重登后生效） |
| GRUB 超时 | 5s | 5s（Windows 双系统，保留菜单可选） |
| GUI 校验 | — | 62 项通过 / 0 项失败（状态感知，随当前配置分支） |
| 重启前体检 | — | 22 项通过 / 0 项失败 |

> 上表为**首轮部署后的历史快照**：字体、主题、Dock 已按 ADR-07 回退，
> GRUB 按 ADR-03 保留 5s，当前实际值以 `./scripts/99-verify.sh` 输出为准。
> `99-verify.sh` 已改为状态感知：定制态与回退态两套断言都能零失败，
> 恢复 Inter / WhiteSur 时无需再改脚本。

## 快速开始

```bash
cd ~/CodeBuddy/work/linux-tune_SuonaOS

# 1. 采集基线（只读，随时可跑）
./scripts/00-preflight.sh

# 2. 部署基础工具链（需要 sudo）
./scripts/01-install-base.sh

# 3. 按阶段执行后续脚本
./scripts/02-network-mirrors.sh
./scripts/03-perf-tune.sh
./scripts/04-devtools.sh
./scripts/05-cjk-fonts.sh
./scripts/06-theme-whitesur.sh
./scripts/07-ime-fcitx5.sh

# 4. 重启前体检（22 项，防开不了机）
./scripts/preboot-check.sh

# 5. 重启后复核
./scripts/99-verify.sh
```

## 出问题了怎么办

```bash
./scripts/rescue.sh --dry-run    # 预览抢救动作
./scripts/rescue.sh              # 还原 GRUB + 移除新增配置 + 恢复被禁用服务
./scripts/rescue.sh --themes-only # 只重置主题（能进桌面但界面崩）
./scripts/rollback.sh --list     # 按批次精确回滚
```

完整的四级恢复流程（GRUB 菜单 → 急救 shell → TTY → Live USB）见
[`docs/98-启动恢复.md`](docs/98-启动恢复.md)。

## 回滚原则

1. **改前必备份**：`backup_file` / `backup_dir` 会把原文件复制到 `backup/<时间戳>/files/<绝对路径>`，并写入 `logs/changes.tsv`。
2. **单一回滚入口**：`./scripts/rollback.sh --list` 查看历史，`--restore <时间戳>` 整体还原，`--restore <时间戳> --only <路径>` 单点还原。
3. **服务级改动**：所有被 `disable` 的单元都会记录原状态，回滚时自动 `enable`。
4. **主题类改动**：全部通过 `gsettings` 与用户级目录（`~/.themes`、`~/.icons`、`~/.local/share/gnome-shell/extensions`），不触碰系统目录，回滚只需恢复 gsettings dump。

## 安全边界

- 不修改分区表、不重装内核、不动 `/boot` 引导项（GRUB 超时调整除外，且会备份 `grub`）。
- 不卸载任何系统自带的 GNOME 组件，仅追加主题。
- 每个脚本可重复执行（幂等），失败时不中断已完成的步骤。

## 项目 Spec

需求、计划、任务看板、进度日志、问题登记与架构决策集中在 [`spec/`](spec/README.md)：

```bash
./scripts/spec-status.sh    # 汇总任务状态、里程碑、未关闭问题
```

维护约定：每次会话结束追加 `spec/05-progress.md`；任务状态变更先改
`spec/04-tasks.md` 再同步 `spec/03-plan.md`；技术选型变更新增 `ADR`。
