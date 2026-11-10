# 03 · 里程碑与阶段编排

| 编号 | 里程碑 | 状态 | 完成度 | 备注 |
|---|---|---|---|---|
| M0 | 环境部署与基线 | done | 100% | 骨架、工具链、镜像、24 项重启前体检 |
| M1 | 性能与开发环境 | done | 100% | 收益已复测归档（`docs/00` 第 9 节） |
| M2 | 美化与输入法 | done | 100% | 桌面主题回退后新增 GRUB/Dock/顶栏美化（ADR-24）与水系壁纸轮换（ADR-25） |
| M3 | 一致性收尾 | done | 100% | TASK-03/04/09/10/20 完成；文档全量同步，99-verify 零失败 |
| M4 | 供电与性能复核 | done | 100% | 电池结论已澄清（健康 100.7%、阈值 75/80）；CPU 锁频为 EC/SMU 状态，断电已恢复 |
| M5 | 归档交付 | done | 100% | `docs/12-交付报告.md`；两套体检零失败，in_progress/planned 归零 |

## 当前：M5 归档交付
M0~M4 全部完成，`99-verify.sh` 零失败、`preboot-check.sh` 零失败。

> 2026-11-05 范围裁剪（ADR-20）：TASK-01 / TASK-29 / TASK-30 不再执行，
> 标记 `cancelled`，`in_progress` 归零。

已完成（本批次）：TASK-05 性能复测归档 · TASK-09/10 措辞与互斥说明 ·
TASK-20 蓝牙音频章节 · ISSUE-06/08/18 收口 · REQ-13/16/19 done ·
急救文档旧路径全清（ADR-22）· 服务精简白名单硬约束（ISSUE-18）。

2026-11-07 收口（ADR-26）：TASK-08 字体维持系统默认（不恢复 Inter/JetBrains Mono）、
TASK-32 GSConnect 已 `apt purge`，`deferred` 归零。
仍挂起：TASK-36 固定 5555 端口（待手机在线，已转 `blocked`）·
ISSUE-12 上游立项报告 v1.1 修订（不影响技术交付）。

## 编排约束
系统级改动前跑 `preboot-check.sh`；每个 TASK 完成更新 `04-tasks.md` + 追加 `05-progress.md`；
涉及 GNOME 扩展/输入法架构的改动先查是否影响候选框主题（ADR-05）。

## 与产品级计划的关系
[`suonaos/03-plan.md`](suonaos/03-plan.md) 是上层商业项目的阶段计划（SM-0 ~ SM-6），
本文件是本机技术原型的里程碑（M0 ~ M5）。两套编号独立：
产品计划的 SDEC 裁决可能反向产生新的技术 TASK，届时在本文件登记并链接来源。
