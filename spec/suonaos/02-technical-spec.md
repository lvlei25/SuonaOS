# 02 · 技术规格与原型对账

## 12 项调优 Checklist 对账 [报告 5.1]

`原型` = 本机 T14 Gen 5 上 `linux-tune` 的实测状态，用于判断技术可行性，**不等同于目标机型已交付**。

| # | 调优项 | 报告要求 | 可验证指标 [报告 5.1] | 原型状态 | 产品动作 |
|---|---|---|---|---|---|
| 1 | 内核参数 | `swappiness=10` / `dirty_ratio=20` / 保留 zen4 + amd-pstate | 冷启动 < 8s | 部分：`swappiness=10`、`dirty_ratio=15`、amd-pstate-epp 生效 | 统一口径，见 05 章 |
| 2 | 电源策略 | TLP + power-profiles-daemon(performance) + amd-pstate-epp | 续航 ≥ 标称 90% | 部分：ppd 已装并设 balanced；TLP 未装 | 目标机型为 mini 无电池，指标 N/A，见 SDEC-03 |
| 3 | 固件更新 | fwupd + LVFS + 锁定机型固件基线 | BIOS/ME 可追溯 | 未做 | 纳入 SREQ-02 |
| 4 | 三重缓冲 | Mutter dynamic triple buffering（GNOME 48 已合入） | 4K 概览 ≥60 FPS | 环境符合：GNOME 50.1，默认开启 | 780M 实测复测 + 上游 patch |
| 5 | 动效曲线 | elementary Pantheon 缓动，开窗 200/关 150/调度 250ms | 无肉眼抖动 | 未做 | 纳入 SREQ-03 |
| 6 | VRR / HDR | 分数缩放 + 满帧率光标 + HDR 录屏 | Display P3 可观测 | 未做 | 纳入 SREQ-03 |
| 7 | 网络栈 | systemd-networkd + NM 双轨 / resolved | Wi-Fi 6E ≥1.2 Gbps | 部分：resolved 启用，单轨 NM | 目标机型需双轨 |
| 8 | DNS | DoH 默认（Cloudflare/阿里） | 解析 < 30ms | 未做 | 纳入 SREQ-05 |
| 9 | 代理 | resolved 智能分流 + Clash Meta GUI | npm/pip/git 直连 | 部分：apt/pip/npm/git 国内镜像已配 | 原型已验证镜像路线可行 |
| 10 | 磁盘加密 | LUKS2 + TPM2 FDE | 开机解密无感 | 未做（原型 ext4 未加密） | **装机时做，不可后补** |
| 11 | 防火墙 | ufw 默认拒绝入站 + nftables | 无开放端口 | 部分：ufw enabled，策略未校验 | 纳入交付清单 |
| 12 | 安全更新 | unattended-upgrades + 公告 | CVE 修复 < 72h | 已启用 | 补公告通道 |

**结论**：12 项中原型已覆盖 5 项（部分）、未做 5 项、环境默认满足 1 项、需装机时一次性完成 1 项。
原型证明了「镜像加速 + sysctl + 服务精简」这条路线可脚本化、可回滚，可直接复用到产品镜像构建。

## 原型可复用的工程资产

| 资产 | 用途 |
|---|---|
| `scripts/00-preflight.sh` | 目标机型基线采集，建兼容性档案 |
| `scripts/99-verify.sh` | 可扩展为报告 M1 要求的「8 步验证清单」 |
| `scripts/preboot-check.sh` | 交付前启动链检查（含双系统感知） |
| `scripts/rollback.sh` / `rescue.sh` | Btrfs 快照方案之外的脚本级回滚兜底 |
| `scripts/bench.sh` | 纯用户态性能基准，排除主题/字体干扰 |
| `spec/` 六层文档体系 | 对应报告 10.2「每个决策写成 wiki、每条命令进 Git」 |

## 原型暴露的真实风险（回填报告 12 章）

| 现象 | 根因 | 对产品的启示 |
|---|---|---|
| GNOME Wayland 下 fcitx5 不自启 | `im-launch` 在 Wayland 分支不启动守护进程 | 首启服务必须用 systemd user unit，不能靠 .desktop |
| Kimpanel 与候选框主题互斥 | Kimpanel 接管绘制，绕过 classicui | 「中文输入法开箱」与「美观候选框」需二选一，写进产品规格 |
| CPU 曾锁 544MHz、性能降 20 倍 | EC/SMU 状态异常，完整断电后恢复；**与电池无关**（复测电池健康 100.7%，见 ISSUE-05） | 锁定机型固件基线 + 交付前完整断电复位验证；保留该复位流程为排查手册条目 |
| 双系统 GRUB 1s 方案不可用 | 需保留菜单选 Windows / recovery | 出货镜像也要保留可恢复引导入口 |
| 主题/字体按用户偏好回退 | 审美主观 | 产品默认外观需可切换，别硬编码 |
| 蓝牙耳机连接后不自动播放 | WirePlumber 残留手动固定的默认输出，且已有流不迁移 | 镜像预置 `module-switch-on-connect`，并清空 `default-nodes` 中的 `configured` 锁定项 |
| 项目目录改名致绝对路径软链断裂 | dotfiles 用绝对路径软链 | 产品镜像用相对路径或安装到固定路径，禁止后期改名（ADR-12） |

## 本地 LLM 路径 [报告 7.1 / 7.2]

| 步骤 | 动作 | 验收 |
|---|---|---|
| 1 | ROCm 7.2+，自动检测 gfx1103 / gfx1151 | `rocminfo` 识别 GPU |
| 2 | `HSA_OVERRIDE_GFX_VERSION=gfx1103` 写入 `/etc/profile.d/rocm-override.sh` | 用户无感 |
| 3 | Ollama + systemd 开机自启 | 服务 active |
| 4 | Qwen3-14B Q4_K_M（8.9GB）预下载到 `/opt/suonaai/models/` | 首次开机可用 |
| 5 | Open WebUI `localhost:8080` 桌面快捷方式 | 可访问 |
| 6 | Q4/Q5/Q8 一键切换脚本 | 切换后可用 |

指标：14B Q4 ≥30 tok/s；30B-A3B ~70 tok/s；8B 多模型常驻 3–4 个。
**原型机不能验证此项**：当前 T14 Gen 5 为 14 GiB + 740M，非 UM870 64GB + 780M，须在目标机型实测。

## 国产软件适配 [报告 6.1]

11 款中 8 款可直接装、钉钉需 `patchelf --clear-execstack` + `libgbm.so` 软链、
WPS 需 `libglu1-mesa`、QQ 音乐需 `libfuse2`、向日葵 Wayland 完全不工作 → 替换 RustDesk、
腾讯会议屏幕共享需 X11 会话后备。合规姿态见 SDEC-02。
