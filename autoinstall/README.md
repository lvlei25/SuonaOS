# autoinstall（镜像骨架）

> 状态：**未实测**。当前只用于把「装机应该做什么」写清楚，不构成可交付镜像。
> 依赖：UM870 到货 + SDEC-01/02 裁决 + SREQ-09 快照方案定稿。

## 文件

| 文件 | 作用 |
|---|---|
| `user-data.yaml` | Ubuntu autoinstall 应答文件：locale / 用户 / 分区 / 软件包 / late-commands |
| `meta-data` | NoCloud 数据源的实例标识 |
| `software-list.tsv` | 11 款国产软件「可达性检测」清单（供 `29-suona-firstboot.sh` 读取） |

## 为什么现在只是骨架

| 前置条件 | 当前状态 | 影响 |
|---|---|---|
| UM870 到货 | 未到（原型机是 T14） | 分区布局、驱动、ROCm 支持都无法在真机验证 |
| SDEC-02「预装 vs 开箱可达」 | 未裁决 | `packages:` 里不敢放第三方 deb，只放官方源软件 |
| SREQ-09 快照方案 | ext4 + Timeshift（本机） | 目标机若要 Btrfs + snapper，`storage:` 段要改 |

## 怎么用（虚拟机先验）

```bash
# 1) 准备 Ubuntu 26.04 ISO 与一个空虚拟机（>=4C/8G/64G）
# 2) 把本目录挂到 ISO 根，或做成第二张 U 盘
# 3) 启动参数：
#    autoinstall ds=nocloud;s=/cdrom/autoinstall/
# 4) 装完进系统后：
./scripts/step-verify.sh
./scripts/29-suona-firstboot.sh --report
./scripts/30-llm-verify.sh
```

## 明确不做

- 不静默安装第三方 `.deb`（合规风险，等 SDEC-02）
- 不预下载大模型（8.9 GB，且涉及模型分发条款）
- 不在 `late-commands` 里改分区表或引导项（出问题无法恢复）
