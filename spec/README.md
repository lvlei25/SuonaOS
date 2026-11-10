# Spec 体系

项目单一事实来源：需求、计划、任务、进度、问题、决策。
文档与实际配置不一致时以实际配置为准，并登记 `06-issues.md`。

| 文件 | 作用 |
|---|---|
| `00-upstream.md` | 上游立项报告索引与差异登记 |
| `01-charter.md` | 章程：目标、非目标、约束、成功标准 |
| `02-requirements.md` | 需求清单 `REQ-xx` |
| `03-plan.md` | 里程碑 `M-xx` 与阶段编排 |
| `04-tasks.md` | 任务看板 `TASK-xx`（状态列供脚本统计） |
| `05-progress.md` | 时间线日志，只追加不改写 |
| `06-issues.md` | 问题登记 `ISSUE-xx` |
| `07-decisions.md` | 决策记录 `ADR-xx`，旧结论不改写 |

状态：`planned` / `in_progress` / `done` / `blocked` / `reverted` / `cancelled` / `deferred`。

维护约定：会话结束追加 `05-progress.md`；任务状态变更先改 `04-tasks.md` 再同步 `03-plan.md`；
技术选型变更新增 ADR；回退改 `reverted` 并记原因。

## 产品级 Spec（上层）

[`suonaos/`](suonaos/README.md) 是依据《SuonaOS 正式立项报告 v1.0》编写的产品规格与阶段计划，
使用独立的 `SREQ / SM / S-xx / SR / SDEC` 编号，与本目录的技术 spec 不混用。
立项报告的索引与差异登记见 `00-upstream.md`。

快速查看：`./scripts/spec-status.sh`
