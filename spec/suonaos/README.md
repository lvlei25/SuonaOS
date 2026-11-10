# SuonaOS 立项 Spec 计划

本目录把《SuonaOS · Ubuntu 一人公司机器 · 正式立项报告 v1.0》（2026-09-10）
转成可跟踪、可验收的产品与技术规格。**与 `../` 下的 `linux-tune` 技术 spec 是两套编号体系**：

| 体系 | 范围 | 编号 | 关系 |
|---|---|---|---|
| `spec/suonaos/` | 商业产品 SuonaOS 整机 | `SREQ / SM / S-xx / SR / SDEC` | 上层 |
| `spec/*.md` | 本机 Ubuntu 调优原型 | `REQ / M / TASK / ISSUE / ADR` | 下层，`02-technical-spec.md` 中作为原型证据 |

来源标注约定：`[报告 5.1]` 指立项报告第 5.1 节；`[原型]` 指 `linux-tune` 已实测结果。

| 文件 | 内容 |
|---|---|
| `01-product-spec.md` | 产品定义四层、目标用户、需求清单 |
| `02-technical-spec.md` | 技术栈、12 项调优对账、本地 LLM 路径 |
| `03-plan.md` | **阶段计划、里程碑重排、关键路径、待裁决项** |
| `04-tasks.md` | 任务分解、依赖、本周清单 |
| `05-acceptance-risks.md` | 可量化验收指标、风险矩阵 |
| `06-milestone-audit.md` | **SM-0 / SM-1 核验表模板**（复制后填写） |

状态：`planned / in_progress / done / blocked / deferred / cancelled`。

维护约定：里程碑状态变化改 `03-plan.md`；任务状态改 `04-tasks.md`；
报告修订后的差异登记到 `../00-upstream.md`；技术验证结论回填 `02-technical-spec.md` 对账表。
