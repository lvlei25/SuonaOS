# 08 · 8 步验证清单 v1

> 对应任务 **S-12**（报告正文缺失，由原型脚本补齐）。
> 版本 **v1.0** / 2026-11-06 / 状态：**已定义，待产品级评审**。
> 驱动脚本：`scripts/step-verify.sh`（本文件第 4 节）
> 上游依据：`05-acceptance-risks.md` A-21、`06-milestone-audit.md` B2/B3。

## 1. 定位与边界

本清单用于**单机交付前验收**，回答一个问题：这台机器能否放心交到用户手里。

- **适用**：原型机（T14 Gen 5）与目标机型（UM870）共用同一套步骤与判据。
- **不适用**：采购、招聘、域名、商标等非技术项，见 `06-milestone-audit.md`。
- **数据纪律**：原型机结果必须标注 `[原型]`，不得替代目标机型验收（A-21 判据）。
- **禁止**：「跑过了」「看着正常」「挺流畅」这类无原始输出的结论。

## 2. 判定规则

每一步只能落在四个状态之一，**不允许人工把 NA 改成 PASS**：

| 状态 | 含义 | 计数 |
|---|---|---|
| `PASS` | 命令执行成功且全部量化判据满足 | 计入通过 |
| `FAIL` | 有判据不满足，或命令报错 | 计入失败，**阻断交付** |
| `NA` | 本机架构性不适用（如 ext4 无 Btrfs 快照），需写明理由 | 不计入通过 |
| `TOOL_MISSING` | 验证工具尚未交付（S-31 / S-44），无法判定 | 不计入通过 |

汇总口径：`PASS / 8` 才是通过率；`NA` 与 `TOOL_MISSING` **必须单列**，
不得用 8 减去失败数来宣称通过。`FAIL > 0` 时脚本退出码非 0。

## 3. 八步定义

### 第 1 步 · 硬件与固件基线

| 项 | 内容 |
|---|---|
| 工具 | `scripts/00-preflight.sh` |
| 命令 | `./scripts/00-preflight.sh` |
| 原始输出 | `baseline/<RUN_ID>/`（26 个文件） |
| 量化判据 | ① 目录生成且文件数 ≥ 20；② 含机型、内核、CPU、内存、磁盘、供电 6 类字段；③ 无 `command not found` |
| 失败处置 | 补依赖后重跑；缺字段说明采集项与机型不符，需改脚本 |
| 本机状态 | `PASS [原型]` |

### 第 2 步 · 启动链完整性

| 项 | 内容 |
|---|---|
| 工具 | `scripts/preboot-check.sh` |
| 命令 | `./scripts/preboot-check.sh` |
| 原始输出 | `logs/<RUN_ID>-preboot-check.log` |
| 量化判据 | `失败 0` 且 `警告 0`；另需 `grub-script-check` 通过、当前内核条目存在、`display-manager.service` 链接有效 |
| 失败处置 | **禁止重启**，先按输出提示修复或 `rollback.sh --restore` |
| 本机状态 | `PASS`（24 项全过） |

### 第 3 步 · 性能基准

| 项 | 内容 |
|---|---|
| 工具 | `scripts/bench.sh` |
| 命令 | `./scripts/bench.sh` |
| 原始输出 | `logs/step-verify-<RUN_ID>/03-bench.log` |
| 量化判据 | ① python 求和 1e7 ≤ 0.60s；② sha256 ≥ 800 MB/s；③ 磁盘写 ≥ 500 MB/s；④ CPU 频率均值 ≥ 上限的 50%；⑤ 无 `governor=performance` 下的异常低值 |
| 失败处置 | 先排除 EC/SMU 锁频（完整断电复位），再查散热与电源配置。**不要先怀疑主题/字体**（ISSUE-01 教训） |
| 本机状态 | `PASS [原型]`（0.13s / 1036 MB/s / 1868 MB/s / 2712MHz） |

> 判据为何是绝对值：bench.sh 的注释值（0.4s / 1000+ MB/s）来自同一机型实测，
> 留 50% 余量后作为下限，避免把「慢 2 倍」当成正常波动。

### 第 4 步 · 系统配置

| 项 | 内容 |
|---|---|
| 工具 | `scripts/99-verify.sh`（性能优化 + 网络加速 + 开发环境三段） |
| 命令 | `./scripts/99-verify.sh` |
| 原始输出 | `logs/step-verify-<RUN_ID>/04-verify.log` |
| 量化判据 | 该脚本 `失败 0`；且 zram 已激活、`swappiness ≤ 20`、BBR 生效、冗余单元为 `disabled` |
| 失败处置 | 按 ✗ 项对应文档修；脚本本身过时按 ADR-21 改断言，**不许跳过** |
| 本机状态 | `PASS`（62 项全过） |

### 第 5 步 · 输入法

| 项 | 内容 |
|---|---|
| 工具 | `scripts/99-verify.sh` 输入法段 + 人工目视 |
| 命令 | `systemctl --user is-active fcitx5.service`、`fcitx5-remote -n`、`fcitx5-configtool` |
| 原始输出 | `logs/step-verify-<RUN_ID>/05-ime.log` + 候选框截图（人工） |
| 量化判据 | ① 服务 `active` 且 `enabled`；② `GTK_IM_MODULE=fcitx`；③ `fcitx5-remote -n` 非空；④ 实际输入可出中文；⑤ 候选框主题与 `classicui.conf` 一致 |
| 失败处置 | 自启查 systemd 服务（不是找 autostart）；主题不刷新用 `systemctl --user restart` |
| 本机状态 | `PASS`（自动 5/5；候选框人工确认） |
| 已知取舍 | Shell 自身输入框因禁 Kimpanel 而走 ibus，属 ADR-05 决定，**不算 FAIL** |

### 第 6 步 · 国产软件 11 款 + 屏幕共享

| 项 | 内容 |
|---|---|
| 工具 | `suona-firstboot` 自检（**未交付**，S-31） |
| 命令 | 无 |
| 量化判据 | ① 11 款均可启动；② Wayland 下屏幕共享可用；③ 必要时可回退 X11 会话 |
| 本机状态 | `TOOL_MISSING`（原型机未安装这批软件；脚本不存在） |
| 后果 | 该项未通过前，SM-1 不能判 `done`；不得用「本机没装」冒充通过 |

### 第 7 步 · 本地 LLM

| 项 | 内容 |
|---|---|
| 工具 | `llm-verify.sh`（**未交付**，S-44） |
| 命令 | 无（本机 `ollama` 未安装） |
| 量化判据 | ① ROCm 正确识别 GPU；② `ollama` active；③ 14B ≥ 30 tok/s、30B-A3B ≈ 70、8B 常驻 3–4（A-xx 指标） |
| 本机状态 | `TOOL_MISSING`（无 AMD GPU 加速环境、未装 Ollama） |
| 后果 | 同第 6 步，不得以「本机不适用」替代目标机型实测 |

### 第 8 步 · 回滚与安全

| 项 | 内容 |
|---|---|
| 工具 | `scripts/rollback.sh --list`、`scripts/rescue.sh --dry-run`、`ufw` |
| 命令 | 见上 |
| 原始输出 | `logs/step-verify-<RUN_ID>/08-rollback.log` |
| 量化判据 | ① `--list` 至少 1 个批次；② `rescue.sh --dry-run` 可执行且列出动作；③ `ufw` 状态可读；④ Btrfs 快照 / LUKS 按机型能力判定 |
| 失败处置 | 无备份批次属严重缺陷，禁止交付 |
| 本机状态 | `PASS [原型]`（5 批次；ufw **未启用**，需产品决策）；Btrfs/LUKS 为 `NA`（ext4 单分区，未加密） |

> `ufw` 不活动不等于失败，但必须在交付记录里写明「未启用」，
> 由产品决定是否在目标机型默认开启——**不能默认沉默**。

## 4. 驱动方式

```bash
./scripts/step-verify.sh                       # 跑 1~5、8；6/7 标 TOOL_MISSING
cat logs/step-verify-<RUN_ID>/summary.txt      # 汇总与逐项说明
ls  logs/step-verify-<RUN_ID>/                 # 每步原始输出
```

脚本只读，不修改系统。第 6/7 步不会伪造通过。
输出目录即交付证据，**不要删除**；`--list` 类只读命令失败也不会自动回滚或修复。

## 5. 工具缺口与交付物映射

| 步 | 缺口 | 交付物 | 阻塞的里程碑 |
|---|---|---|---|
| 6 | 国产软件自检 | S-31 `suona-firstboot` | SM-1 判定、SM-2 |
| 7 | LLM 性能实测 | S-44 `llm-verify.sh` | SM-2 指标回填 |
| 8 | 每台交付前执行 | S-51（依赖本清单 S-12） | 首批交付 S-52 |

## 6. 本机（原型）实测结论 2026-11-06

| 步 | 状态 | 依据 |
|---|---|---|
| 1 硬件基线 | `PASS [原型]` | `baseline/20261103-201447/` 26 文件 |
| 2 启动链 | `PASS` | 24/0/0 |
| 3 性能基准 | `PASS [原型]` | python 0.13s / sha256 1036 MB/s |
| 4 系统配置 | `PASS` | 99-verify 45/0 |
| 5 输入法 | `PASS` | 服务 active + 5/5 检查 |
| 6 国产软件 | `TOOL_MISSING` | S-31 未交付 |
| 7 本地 LLM | `TOOL_MISSING` | S-44 未交付 |
| 8 回滚与安全 | `PASS [原型]` | 5 批次；ufw 未启用已登记 |

**结论：`PASS 6 / 8`，`TOOL_MISSING 2`，`FAIL 0`。**
按 §2 口径，**不能**宣称「8 步通过」；SM-1 仍为 `partial`，
第 6/7 步须在目标机型 + 工具交付后补测。

## 7. 评审与变更

| 版本 | 日期 | 变更 | 评审 |
|---|---|---|---|
| v1.0 | 2026-11-06 | 首次定义：8 步判据、四状态、缺口映射、原型实测 | 待产品级评审 |

变更规则：新增判据必须写明**量化阈值与来源**；放宽阈值需记录理由，
不得为了让当前机器通过而调低标准（同 ADR-21 精神）。
