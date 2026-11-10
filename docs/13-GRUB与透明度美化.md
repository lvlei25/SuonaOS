# 13 · GRUB 与透明度美化

> 脚本：`scripts/09-grub-transparency.sh`
> 备份批次：`backup/20261106-075444/`（`/etc/default/grub` + `grub.cfg`）
> 生效条件：**GRUB 需重启 / 顶栏需注销重登 / Dock 即时生效**

## 1. 做了什么

| 部分 | 方案 | 生效时机 |
|---|---|---|
| GRUB 菜单 | [grub2-themes](https://github.com/vinceliuice/grub2-themes) 的 **Vimix**，2K、白色图标 | 重启 |
| Dock（底部） | dash-to-dock 原生 `FIXED` + `background-opacity 0.5` | 即时 |
| 顶栏 | Blur my Shell 扩展，毛玻璃（brightness 0.6 / sigma 30） | 注销重登 |

三者互不依赖：Dock 不装扩展也能透明，顶栏不装主题也能毛玻璃。

## 2. GRUB 主题

### 2.1 安装结果

```
/etc/default/grub:
  GRUB_THEME="/usr/share/grub/themes/vimix/theme.txt"
  GRUB_GFXMODE=2560x1440,auto
  GRUB_TIMEOUT=5            ← 未改动，双系统保留（ADR-03）

/boot/grub/grub.cfg:
  set gfxmode=2560x1440,auto
  set theme=($root)/usr/share/grub/themes/vimix/theme.txt
```

主题文件 16 MB，位于 `/usr/share/grub/themes/vimix/`。
`update-grub` 时确认仍找到 **Windows Boot Manager** 与 **recovery mode**，
双系统入口没有被主题安装破坏。

### 2.2 分辨率取舍（本机 3072×1920，16:10）

`install.sh -s 2k` 生成的是 **2560×1440（16:9）** 资源，在 16:10 屏上会有
约 **11% 纵向拉伸**。三种选择：

| 方案 | 效果 | 代价 |
|---|---|---|
| `-s 2k`（当前） | 清晰，轻微纵拉 | 无 |
| `-s 1080p` | 更轻、拉伸更明显 | 模糊 |
| `-c 3072x1920` | 菜单按原生分辨率排版 | 背景图仍 2560×1440 拉伸，边缘可能被裁 |

视觉上 2K 方案最稳，**不建议用 4K**：3072 宽的屏承受 3840 资源只会增加加载时间。

### 2.3 换主题 / 换图标

```bash
cd ~/CodeBuddy/work/linux-tune_SuonaOS/vendor/grub2-themes
sudo ./install.sh -t tela      -i white -s 2k    # 极简
sudo ./install.sh -t stylish   -i color -s 2k    # 带色彩
sudo ./install.sh -t whitesur  -i whitesur -s 2k # macOS 风
```

可选项：`-t tela|vimix|stylish|whitesur`、`-i color|white|whitesur`、
`-s 1080p|2k|4k|ultrawide`。每次安装都会重写 `GRUB_THEME` 并 `update-grub`。

### 2.4 验证（不重启也能查）

```bash
grep -E '^GRUB_THEME|^GRUB_GFXMODE|^GRUB_TIMEOUT' /etc/default/grub
sudo grep -m2 -E 'set theme|set gfxmode' /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg && echo OK
./scripts/preboot-check.sh        # 必须 0 失败再重启
```

> 主题文件丢失不会导致无法启动，GRUB 会自动回退到文本菜单——这是它比
> 改内核参数安全的地方。真正的风险是 `grub.cfg` 语法错误，所以每次都要
> `grub-script-check` + `preboot-check.sh`。

## 3. Dock 透明度

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.5
```

| 键 | 取值 | 说明 |
|---|---|---|
| `transparency-mode` | `DEFAULT` / `FIXED` / `DYNAMIC` | `DEFAULT` 跟随主题；`FIXED` 固定；`DYNAMIC` 有窗口时变透明 |
| `background-opacity` | `0.0` ~ `1.0` | 数值越小越透；`0` 完全透明，图标会糊在壁纸上 |

调深浅只改第二个值：

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.35  # 更透
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.7   # 更实
```

> 建议不要低于 `0.4`：本机 3072×1920 高分屏 + 深色壁纸时，
> 0.3 以下图标边缘会和背景混在一起。

## 4. 顶栏（工具栏）透明度

### 4.1 为什么必须装扩展

GNOME Shell 的顶栏背景写在 shell 主题 CSS 里，**没有对应的 gsettings 开关**。
不装扩展只有两条路：换整个 shell 主题（会牵连全部界面），或改系统 CSS（升级即失效）。
Blur my Shell 通过接管顶栏背景绘制实现毛玻璃，是侵入最小的方案。

### 4.2 已设参数

| 键 | 值 | 作用 |
|---|---|---|
| `blur` | `true` | 开启顶栏模糊 |
| `customize` | `true` | 启用下方自定义值 |
| `override-background` | `true` | 由扩展接管背景，否则只是在原黑底上叠模糊 |
| `brightness` | `0.6` | 背景明度，越低越暗越透 |
| `sigma` | `30` | 模糊半径 |
| `static-blur` | `false` | 不强制静态模糊 |
| `unblur-in-overview` | `false` | 概览里保持模糊 |
| `force-light-text` | `false` | 不强制浅色文字 |

调参（扩展加载后可直接 `gsettings`，无需重启）：

```bash
export GSETTINGS_SCHEMA_DIR="$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas"
S=org.gnome.shell.extensions.blur-my-shell.panel
gsettings set $S brightness 0.4   # 更暗更透
gsettings set $S sigma 45         # 更糊
gsettings set $S blur false       # 关模糊（退回纯色）
```

### 4.3 图形化设置

```bash
gnome-extensions prefs blur-my-shell@aunetx
```

可分别调顶栏、Dash、概览、应用文件夹、锁屏的模糊与颜色。

## 5. 回滚

```bash
# GRUB：恢复备份 + 重新生成
sudo cp ~/CodeBuddy/work/linux-tune_SuonaOS/backup/20261106-075444/files/etc/default/grub /etc/default/grub
sudo update-grub
sudo grub-script-check /boot/grub/grub.cfg

# 只移除主题保留其他 GRUB 设置
sudo sed -i '/^GRUB_THEME=/d' /etc/default/grub
sudo update-grub

# Dock
gsettings reset org.gnome.shell.extensions.dash-to-dock transparency-mode
gsettings reset org.gnome.shell.extensions.dash-to-dock background-opacity

# 顶栏
gnome-extensions disable blur-my-shell@aunetx    # 或从 enabled-extensions 移除
rm -rf ~/.local/share/gnome-shell/extensions/blur-my-shell@aunetx
```

主题目录可单独删：`sudo rm -rf /usr/share/grub/themes/vimix`。

## 6. 踩坑记录

| 现象 | 原因 | 处理 |
|---|---|---|
| `gnome-extensions enable` 报「扩展不存在」 | Shell 缓存了会话启动时的扩展列表，新装扩展本会话不可见 | 直接写 `gsettings set org.gnome.shell enabled-extensions`，注销重登 |
| `gsettings --schemadir` 报「未知命令」 | 本机 glib 版本不接受该参数位置 | 改用 `GSETTINGS_SCHEMA_DIR=<dir> gsettings ...` |
| 顶栏设了没变化 | 扩展未在当前会话加载 | 注销重登，不是参数没写进去 |
| `override-background` 没开，只有一层灰 | 模糊叠在不透明黑底上 | 必须开 `override-background true` |
| GRUB 菜单文字偏长/图标变形 | 2K(16:9) 资源在 16:10 屏上纵拉 | 换 1080p 或 `-c` 自定义分辨率 |
| `backup_file /boot/grub/grub.cfg` 失败 | `cp` 无 root 读不了 | 用 `sudo cp` 到 backup 目录 |

## 7. 交付状态

| 项 | 状态 |
|---|---|
| GRUB 主题配置 | 已写入，`grub.cfg` 语法通过，`preboot-check` 24/0/0 |
| GRUB 视觉效果 | **待重启确认**（本会话看不到） |
| Dock 透明度 | 已生效（0.5） |
| 顶栏毛玻璃 | 参数已写入，**待注销重登确认** |
| 回滚路径 | 备份批次 `20261106-075444`，脚本 `09` 可复跑 |
