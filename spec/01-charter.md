# 01 · 项目章程

## 目标
在 Ubuntu 26.04 LTS / GNOME 50 (Wayland) 笔记本上完成系统优化与个性化，
并把全部改动沉淀为可复用、可回滚、可复现的脚本与文档。

## 非目标
不改分区表 / 不重装内核 / 不动 EFI 引导项；不追求极限跑分；不做多机批量分发。

## 环境与约束

| 项 | 值 |
|---|---|
| 项目路径 | `~/CodeBuddy/work/linux-tune_SuonaOS/`（2026-11-05 改名，见 ADR-12） |
| 机型 | ThinkPad T14 Gen 5 (21MCCTO1WW) |
| CPU / GPU | Ryzen 5 PRO 8540U / Radeon 740M |
| 内存 / 磁盘 | 14 GiB / NVMe 288G ext4 |
| 系统 | Ubuntu 26.04.1 LTS，内核 7.0.0-42，GNOME Shell 50.1 |
| 会话 | Wayland（GDM） |
| 双系统 | 是，Windows 11 在 nvme0n1p3，GRUB 超时保留 5s |
| 电池 | SMP 5B11H56415 Li-poly，设计 52.57 Wh，健康 100.7%，循环 2 次，充电阈值 75/80（ISSUE-05 已澄清） |
| 权限 | 免密 sudo 已配置 |
| 改动尺度 | 标准：允许 sysctl / 服务调整，每步备份 + 一键回滚 |
| 执行模式 | AI 只生成命令，用户手动粘贴（ADR-08） |

## 成功标准

| 指标 | 目标 | 当前 |
|---|---|---|
| 改动脚本化、幂等 | 100% | 达成 |
| 可回滚 | `rollback.sh` / `rescue.sh` | 达成 |
| 文档覆盖每阶段 | ≥1 篇/阶段 | 达成 |
| 体检通过率 | 100% | 未达成（字体回退导致 4 项失败） |
| 开机时间 | < 20s | 未复测 |
| 输入法自启 | 无需人工 | 达成（systemd） |
| 文档与配置一致 | 零漂移 | 未达成（ISSUE-06） |

## 回退原则
改前 `backup_file` 并登记 `logs/changes.tsv`；服务禁用记录 `logs/disabled-units-*.tsv`；
主题/字体均为用户级文件，可直接删除恢复。
