# 04 · 任务分解

编号 `S-xx`，与 `linux-tune` 的 `TASK-xx` 区分。状态列供统计。

## 立即执行：立项报告「本周 5 件事」重排 [报告 13]

原清单对应 2026-09-10 当周，已过期 8 周。按当前日期重排为 W1（11-04 → 11-10）：

| 编号 | 原事项 | 当前状态 | 重排动作 | 验收 |
|---|---|---|---|---|
| S-01 | 抢注 suonaos.com / .org / .cn（¥80–200） | planned | 立即核验是否仍可注册，未被抢注则当天完成 | 3 个域名持有凭证 |
| S-02 | 下单 UM870 barebones ×3（¥18,000）+ M920q ×2（¥2,000）+ Mac mini M4 ×1（¥3,000） | blocked | **待 SDEC-01**：确认采购清单不含 T14s 后执行 | 到货 + 兼容性档案 |
| S-03 | 确定 1 名系统工程师 + 1 名 AI 工程师 | planned | 核验是否已到位，纳入 SM-0 核验报告 | 人员名单 |
| S-04 | 商标检索「唢呐」+「SuonaOS」（sbj.cnipa.gov.cn） | planned | 与域名同批完成 | 检索报告 |
| S-05 | 第一篇公众号《我为什么做 SuonaOS》1000 字 + 封面 | planned | 可先行，不依赖硬件 | 发布链接 + 阅读数 |

## W1 核验与裁决（最高优先级）

| 编号 | 任务 | 状态 | 依赖 | 验收 |
|---|---|---|---|---|
| S-10 | 核验 SM-0：UM870×5 / 团队 / 域名是否实际完成 | blocked | — | 缺 5 类外部凭证（域名/发票/人员/商标/发布）；已建 `06-milestone-audit-2026-11-06.md`，A 部分全部 `unknown` |
| S-11 | 核验 SM-1：v0.1 是否跑过 8 步验证清单 | done | S-12 | 已核验：SM-1 = `partial`，8 步 `PASS 6/8` + 2 步工具缺失（S-31/S-44） |
| S-12 | 定义「8 步验证清单 v1」（报告正文缺失） | done | — | `08-step-verification.md` v1.0（量化判据 + 四状态）+ `scripts/step-verify.sh` 驱动；待评审 |
| S-13 | 裁决 SDEC-01 笔记本档残留 | planned | S-10 | `03-plan.md` 标记裁决结论 |
| S-14 | 裁决 SDEC-02 合规姿态 | planned | — | 产品话术与 SREQ-05/07 口径更新 |
| S-15 | 裁决 SDEC-03 / 05 指标口径 | planned | — | `05-acceptance-risks.md` 更新 |
| S-16 | 裁决 SDEC-04：SM-2 压缩范围或顺延 | planned | S-10~S-12 | 新日期写入 `03-plan.md` |

## W2 硬件与镜像

| 编号 | 任务 | 状态 | 依赖 | 验收 |
|---|---|---|---|---|
| S-20 | UM870 到货验收 + 兼容性档案 | planned | S-02, S-13 | 每台一档：BIOS/固件/功耗/外设 |
| S-21 | Ubuntu 26.04 基线镜像 + Btrfs 快照（5 个可回滚）[报告 5.3] | planned | S-20 | 开机可选 5 个快照 |
| S-22 | LUKS2 + TPM2 FDE（装机时一次性）[报告 5.1 #10] | planned | S-21 | 解密无感 |
| S-23 | 12 项调优 Checklist 移植（复用原型脚本） | planned | S-21 | `02-technical-spec.md` 对账表 12 项全绿 |
| S-24 | fwupd + LVFS 固件基线锁定 | planned | S-20 | 固件版本可追溯 |

## W3 国产软件与桌面

| 编号 | 任务 | 状态 | 依赖 | 验收 |
|---|---|---|---|---|
| S-30 | 11 款国产软件适配（钉钉 patchelf / WPS 依赖 / libfuse2 / RustDesk 替换） | planned | S-14, S-21 | 11 款可启动 |
| S-31 | `suona-firstboot` 服务：依赖/镜像/Wayland/字体检测 | planned | S-30 | 首次开机 0 手工配置 |
| S-32 | Flatpak 中科大/阿里镜像 | planned | S-21 | ≥10 MB/s |
| S-33 | X11 会话后备（腾讯会议共享）+ 登录界面说明 | planned | S-21 | 可切换 |
| S-34 | GNOME 50 三重缓冲 780M 复测 + 动效曲线 | planned | S-20 | 4K 概览 ≥60 FPS |
| S-35 | Control Center / Software Center / Welcome | planned | S-21 | 首次开机引导可走通 |
| S-36 | fcitx5 自启（systemd user unit）+ 候选框主题 | planned | S-21 | 登录即用，原型已验证 |

## W4 本地 LLM

| 编号 | 任务 | 状态 | 依赖 | 验收 |
|---|---|---|---|---|
| S-40 | ROCm 7.2+ 安装 + gfx1103 自动检测 | planned | S-20 | `rocminfo` 识别 |
| S-41 | `HSA_OVERRIDE_GFX_VERSION` profile.d 注入 | planned | S-40 | 用户无感 |
| S-42 | Ollama + systemd 自启 + Qwen3-14B Q4 预下载 | planned | S-40 | 首次开机可用 |
| S-43 | Open WebUI / localhost:8080 快捷方式 + Q4/Q5/Q8 切换脚本 | planned | S-42 | 可对话、可切换 |
| S-44 | tok/s 实测（14B ≥30 / 30B-A3B ~70 / 8B 常驻 3–4） | planned | S-42 | 指标表回填 `05-acceptance-risks.md` |
| S-45 | 中文 RAG 模板（AnythingLLM 挂载工作文件夹） | planned | S-43 | 10 分钟搭出个人知识库 |

## W5–W6 集成与交付

| 编号 | 任务 | 状态 | 依赖 | 验收 |
|---|---|---|---|---|
| S-50 | v0.3 内部版集成 | planned | S-23, S-30, S-42 | 全栈可跑 |
| S-51 | 8 步验证清单全过 | planned | S-12, S-50 | 每台交付前执行 |
| S-52 | 首批 50 台交付 + 远程调试 + 7 天退换 | planned | S-51 | 交付记录 |
| S-53 | 用户反馈闭环表 + 1 篇爆款内容 | planned | S-52 | SM-3 验收 |

## 阻塞与依赖总览

```
SDEC-01 ──→ S-02 采购 ──→ S-20 硬件 ──→ W2/W3/W4 全部
SDEC-02 ──→ S-30 国产软件适配
S-10/S-11 核验 ──→ S-16 排期裁决 ──→ W2~W6
S-12 8步清单 ──→ S-51 交付验收
```

未裁决前 W2 之后的全部任务保持 `planned`，不提前启动。
