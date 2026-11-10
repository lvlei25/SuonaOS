#!/usr/bin/env bash
# ============================================================================
# 11-sound-theme.sh - Suona 声音主题（本地合成，零第三方素材）
#   遵循 freedesktop sound-theme 规范，生成到 ~/.local/share/sounds/Suona/
#   再通过 gsettings org.gnome.desktop.sound theme-name 切换
#   音色分三族：木腔（wood） / 瓷击（porcelain） / 哨片（reed） / 低木（lowwood）
#   battery-low / battery-caution 是 gsd-power 的内置事件名，补齐文件即可自动触发
#   全部由 ffmpeg 的 aevalsrc 合成，不含采样素材，故无授权与署名负担
# 用法:
#   ./scripts/11-sound-theme.sh              # 生成 + 安装 + 切换（幂等）
#   ./scripts/11-sound-theme.sh --dry-run    # 只打印将做什么
#   ./scripts/11-sound-theme.sh --list       # 查看事件表与当前状态
#   ./scripts/11-sound-theme.sh --preview    # 逐个试听
#   ./scripts/11-sound-theme.sh --restore    # 恢复安装前的主题
#   ./scripts/11-sound-theme.sh --decay -3   # 调系统音效相对衰减（dB，默认 -6.5）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

THEME="Suona"
DEST="$HOME/.local/share/sounds/$THEME"
STEREO="$DEST/stereo"
ACTION=install
DRY=0

# 系统音效相对应用内容的固定衰减（dB）。
# 背景：GNOME 50 的 org.gnome.desktop.sound 没有「系统音效音量」键，
# 提示音只能与应用共享同一个 sink 音量；而应用内容响度约 -14 LUFS，
# 若提示音峰值也贴 -3.5 dBFS，就会突兀地压过音乐/会议声音。
# 因此在生成端统一压低一档；WirePlumber 的 stream.rules 实测无效
# （pulse 层 stream-restore 会把 media.role=event 的流重置回 100%）。
CONF="$HOME/.config/linux-tune/sound.conf"
SYS_DECAY_DB="-6.5"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# 事件表：事件名|音符合集（频率:音色:增益:延迟毫秒）|目标峰值dB（缺省 -3.5）
# 音色族的衰减与时长在 render() 里统一，保证同族听感一致；
# 峰值在 encode_norm() 里逐文件归一化，避免「通知很轻、快门很炸」。
EVENTS=(
  "bell|880:reed:0.30:0"
  "message|392:wood:0.50:0"
  "message-new-instant|440:wood:0.48:0 587:wood:0.38:150"
  "complete|660:wood:0.45:0 880:wood:0.36:170"
  "dialog-information|1046:porcelain:0.40:0"
  "dialog-warning|587:wood:0.40:0 494:wood:0.35:170 392:wood:0.30:340"
  "dialog-error|196:lowwood:0.55:0 147:lowwood:0.48:230|-2.5"
  "window-attention|1175:porcelain:0.34:0 1175:porcelain:0.28:130"
  "window-question|1318:porcelain:0.32:0"
  "audio-volume-change|1760:porcelain:0.30:0|-7"
  "device-added|587:wood:0.42:0 784:wood:0.35:140"
  "device-removed|784:wood:0.42:0 587:wood:0.35:140"
  "power-plug|659:wood:0.40:0 988:wood:0.33:130"
  "power-unplug|988:wood:0.40:0 659:wood:0.33:130"
  "battery-low|392:lowwood:0.45:0 294:lowwood:0.40:200|-2.5"
  "battery-caution|294:lowwood:0.50:0 247:lowwood:0.45:200 196:lowwood:0.42:400|-2"
  "battery-full|784:wood:0.38:0 988:wood:0.34:150 1318:porcelain:0.28:300"
  "desktop-login|523:reed:0.45:0 659:reed:0.40:250 784:reed:0.45:500"
  "desktop-logoff|784:reed:0.45:0 659:reed:0.40:250 523:reed:0.42:500"
  "dialog-question|1046:porcelain:0.34:0 1318:porcelain:0.30:160"
  "message-new-email|392:wood:0.48:0 523:wood:0.42:180 659:wood:0.34:360"
  "system-ready|587:wood:0.40:0 880:wood:0.36:160 1175:wood:0.30:320"
  "network-connectivity-established|784:wood:0.36:0 1175:wood:0.30:130"
  "network-connectivity-lost|1175:wood:0.36:0 784:wood:0.30:130"
  "service-login|587:reed:0.55:0 880:reed:0.50:300"
  "service-logout|880:reed:0.55:0 587:reed:0.48:300"
  "phone-incoming-call|523:reed:0.55:0 659:reed:0.50:300 523:reed:0.55:640 659:reed:0.50:940"
  "phone-outgoing-busy|392:lowwood:0.45:0 392:lowwood:0.42:260"
  "phone-outgoing-calling|440:reed:0.55:0"
  "suspend-error|196:lowwood:0.52:0 196:lowwood:0.46:300|-2.5"
  "trash-empty|880:porcelain:0.34:0 587:porcelain:0.27:140"
  "alarm-clock-elapsed|523:reed:0.55:0 659:reed:0.50:300 784:reed:0.55:600"
  "camera-shutter|SHUTTER|-4"
  "screen-capture|SHUTTER_LIGHT|-7"
)

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --list) ACTION=list ;;
    --preview) ACTION=preview ;;
    --restore) ACTION=restore ;;
    --decay) SYS_DECAY_DB="${2:--6.5}"; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1（可用 --dry-run / --list / --preview / --restore）" ;;
  esac
  shift
done

cur_theme() { gsettings get org.gnome.desktop.sound theme-name 2>/dev/null | tr -d "'"; }

# ---- list ------------------------------------------------------------------
if [ "$ACTION" = list ]; then
  echo "主题目录: $DEST"
  echo "已生成  : $(ls -1 "$STEREO"/*.oga 2>/dev/null | wc -l) 个事件音"
  echo "事件定义: ${#EVENTS[@]} 个（audio-channel-* 等调试音不覆盖，回落到 freedesktop）"
  echo "当前主题: $(cur_theme)"
  echo "事件音效: $(gsettings get org.gnome.desktop.sound event-sounds)"
  echo "系统音效衰减: ${SYS_DECAY_DB} dB（相对应用内容；--decay 可调）"
  echo
  printf '  %-34s %s\n' "事件" "文件"
  for e in "${EVENTS[@]}"; do
    name="${e%%|*}"
    f="$STEREO/$name.oga"
    printf '  %-34s %s\n' "$name" "$([ -f "$f" ] && echo "✓ $(du -h "$f" | cut -f1)" || echo '—')"
  done
  exit 0
fi

# ---- preview ---------------------------------------------------------------
if [ "$ACTION" = preview ]; then
  have paplay || die "缺少 paplay（apt install pulseaudio-utils）"
  [ "$(cur_theme)" = "$THEME" ] || warn "当前主题不是 $THEME，试听的是文件本身；生效请先执行 $0"
  for e in "${EVENTS[@]}"; do
    name="${e%%|*}"
    f="$STEREO/$name.oga"
    [ -f "$f" ] || { warn "跳过（未生成）: $name"; continue; }
    printf '  ♪ %-34s' "$name"
    paplay "$f" && echo '已播放'
    sleep 0.15
  done
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  latest=""; orig=""
  # 跳过值为 Suona 的批次：重复安装会留下「回滚到 Suona 自己」的无效记录，
  # 只有更早的非 Suona 值才是真正的原始状态
  for d in $(ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | sort); do
    [ -f "$d/sound-theme.txt" ] || continue
    v="$(sed -n 's/^theme-name=//p' "$d/sound-theme.txt" | tr -d "'" | tr -d '"')"
    [ -n "$v" ] && [ "$v" != "$THEME" ] && { latest="$d"; orig="$v"; }
  done
  [ -n "$latest" ] || die "找不到有效备份记录（$BACKUP_DIR/*/sound-theme.txt 中无非 $THEME 值）"
  [ -n "$orig" ] || die "备份文件缺少 theme-name: $latest/sound-theme.txt"
  if [ $DRY -eq 1 ]; then
    log "[dry-run] 恢复 theme-name → $orig"
    log "[dry-run] 备份来源: ${latest#$PROJECT_ROOT/}"
    exit 0
  fi
  gsettings set org.gnome.desktop.sound theme-name "$orig"
  ok "已恢复 sound theme-name = $orig（来自 ${latest#$PROJECT_ROOT/}）"
  warn "主题目录保留在 ${DEST#$HOME/}；如需删除执行 rm -rf $DEST"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/4 检查依赖"
have ffmpeg || die "缺少 ffmpeg（apt install ffmpeg）"
ok "ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')"

step "2/4 合成事件音（$THEME：木腔 / 瓷击 / 哨片）"
[ $DRY -eq 1 ] && warn "[dry-run] 将生成 ${#EVENTS[@]} 个 .oga 到 $STEREO"

# 单音合成 + 多音混合
# 用法: render <输出> "<f:音色:增益:延迟>" ["..."]
render() {
  local out="$1"; shift
  local -a args=() chains=() mix=""
  local idx=0 spec freq timbre gain delay dur decay expr f2 f3
  for spec in "$@"; do
    IFS=: read -r freq timbre gain delay <<<"$spec"
    case "$timbre" in
      wood)      decay=15; dur=0.42 ;;
      porcelain) decay=26; dur=0.30 ;;
      reed)      decay=4.5; dur=0.80 ;;
      lowwood)   decay=8;  dur=0.65 ;;
      *) die "未知音色: $timbre" ;;
    esac
    case "$timbre" in
      wood)
        f2=$((freq*272/100)); f3=$((freq*527/100))
        expr="0.44*exp(-${decay}*t)*(sin(2*PI*${freq}*t)+0.45*sin(2*PI*${f2}*t)+0.20*sin(2*PI*${f3}*t))" ;;
      porcelain)
        f2=$((freq*167/100)); f3=$((freq*257/100))
        expr="0.40*exp(-${decay}*t)*(sin(2*PI*${freq}*t)+0.50*sin(2*PI*${f2}*t)+0.30*sin(2*PI*${f3}*t))" ;;
      reed)
        expr="0.40*(1-exp(-70*t))*exp(-${decay}*t)*sin(2*PI*${freq}*t+0.9*sin(2*PI*5.5*t))" ;;
      lowwood)
        f2=$((freq*190/100)); f3=$((freq*310/100))
        expr="0.50*exp(-${decay}*t)*(sin(2*PI*${freq}*t)+0.40*sin(2*PI*${f2}*t)+0.18*sin(2*PI*${f3}*t))" ;;
    esac
    args+=(-f lavfi -i "aevalsrc='${expr}':s=44100:d=${dur}")
    chains+=("[${idx}:a]volume=${gain},afade=t=in:st=0:d=0.004,adelay=delays=${delay}:all=1,lowpass=f=9000[n${idx}]")
    mix+="[n${idx}]"
    idx=$((idx+1))
  done
  local fc
  fc="$(IFS=';'; printf '%s' "${chains[*]}")"
  ffmpeg -hide_banner -loglevel error -y "${args[@]}" \
    -filter_complex "${fc};${mix}amix=inputs=${idx}:normalize=0,alimiter=limit=0.85" \
    -c:a pcm_s16le "$out" \
    || die "合成失败: $(basename "$out")"
}

# 逐文件峰值归一化后编码：短音效的「响度感」几乎只由峰值决定，
# 统一到同一目标峰值才能避免某些事件过轻、某些过炸。
# 用法: encode_norm <src.wav> <dst.oga> [目标峰值dB]
encode_norm() {
  local src="$1" dst="$2" target="${3:--3.5}"
  local peak gaindb
  # 叠加系统音效衰减：让全部事件一起降一档，事件之间的相对关系不变
  target="$(awk -v t="$target" -v d="$SYS_DECAY_DB" 'BEGIN{printf "%.2f", t+d}')"
  peak="$(ffmpeg -hide_banner -i "$src" -af volumedetect -f null /dev/null 2>&1 \
    | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p' | head -1)"
  [ -n "$peak" ] || die "无法测量峰值: $(basename "$src")"
  gaindb="$(awk -v t="$target" -v p="$peak" 'BEGIN{printf "%.2f", t-p}')"
  # 提升上限 18dB：再高会把合成底噪一起抬起来
  gaindb="$(awk -v g="$gaindb" 'BEGIN{printf "%.2f", (g>18?18:g)}')"
  ffmpeg -hide_banner -loglevel error -y -i "$src" \
    -af "volume=${gaindb}dB" -c:a libvorbis -q:a 5 -ar 44100 -ac 1 "$dst" \
    || die "编码失败: $(basename "$dst")"
}

# 快门：白噪脉冲 + 高频咔哒，两段模拟机械快门
render_shutter() {
  local out="$1" amp="${2:-0.55}"
  local amp2
  amp2="$(awk -v a="$amp" 'BEGIN{printf "%.2f", a*0.62}')"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "anoisesrc=d=0.050:c=white:a=${amp}" \
    -f lavfi -i "aevalsrc='0.5*exp(-90*t)*sin(2*PI*3300*t)':s=44100:d=0.10" \
    -f lavfi -i "anoisesrc=d=0.040:c=white:a=${amp2}" \
    -filter_complex "[0:a]highpass=f=2400,afade=t=out:st=0.012:d=0.038[n0];\
[1:a]afade=t=in:st=0:d=0.002,lowpass=f=6000[n1];\
[2:a]highpass=f=3000,afade=t=in:st=0:d=0.002,afade=t=out:st=0.004:d=0.036,adelay=delays=78:all=1[n2];\
[n0][n1][n2]amix=inputs=3:normalize=0,alimiter=limit=0.85" \
    -c:a pcm_s16le "$out" \
    || die "合成失败: $(basename "$out")"
}

if [ $DRY -eq 1 ]; then
  for e in "${EVENTS[@]}"; do
    rest="${e#*|}"; IFS='|' read -r notes target <<<"$rest"
    printf '  [dry-run] %-34s <- %-48s peak %s dB\n' \
      "${e%%|*}.oga" "$notes" "${target:--3.5}"
  done
else
  mkdir -p "$STEREO"
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  for e in "${EVENTS[@]}"; do
    name="${e%%|*}"; rest="${e#*|}"
    IFS='|' read -r notes target <<<"$rest"
    target="${target:--3.5}"
    case "$notes" in
      SHUTTER)       render_shutter "$TMPD/$name.wav" 0.55 ;;
      SHUTTER_LIGHT) render_shutter "$TMPD/$name.wav" 0.34 ;;
      *)             render "$TMPD/$name.wav" $notes ;;
    esac
    encode_norm "$TMPD/$name.wav" "$STEREO/$name.oga" "$target"
  done
  ok "已生成 $(ls -1 "$STEREO"/*.oga | wc -l) 个事件音（$(du -sh "$STEREO" | cut -f1)，峰值已归一）"
fi

step "3/4 写入 index.theme 并切换"
if [ $DRY -eq 1 ]; then
  log "[dry-run] 写入 $DEST/index.theme"
  log "[dry-run] gsettings set org.gnome.desktop.sound theme-name $THEME"
else
  cat >"$DEST/index.theme" <<'EOF'
[Sound Theme]
Name=Suona
Comment=Suona 木腔提示音（ffmpeg 合成，无第三方采样）
Directories=stereo

[stereo]
OutputProfile=stereo
EOF
  ok "index.theme 已写入"

  # 只在「首次从非 Suona 切过来」时备份；重复执行不覆盖真实原值
  if [ "$(cur_theme)" != "$THEME" ]; then
    BATCH="$BACKUP_DIR/$RUN_ID"
    mkdir -p "$BATCH"
    {
      printf "theme-name=%s\n" "$(gsettings get org.gnome.desktop.sound theme-name)"
      printf "event-sounds=%s\n" "$(gsettings get org.gnome.desktop.sound event-sounds)"
    } >"$BATCH/sound-theme.txt"
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" \
      "org.gnome.desktop.sound theme-name" "${BATCH#$BACKUP_DIR/}/sound-theme.txt" >>"$MANIFEST"
    ok "原主题已备份 → ${BATCH#$PROJECT_ROOT/}/sound-theme.txt"
  else
    ok "已处于 $THEME，跳过重复备份（保留首次原值记录）"
  fi

  gsettings set org.gnome.desktop.sound theme-name "$THEME" \
    && gsettings set org.gnome.desktop.sound event-sounds true \
    && ok "已切换到 $THEME（含事件音效开关）"

  mkdir -p "$(dirname "$CONF")"
  printf '# 由 11-sound-theme.sh 生成（%s）\n# 系统音效相对应用内容的固定衰减（负值=更轻）\nSYS_DECAY_DB="%s"\n' \
    "$(date '+%F %T')" "$SYS_DECAY_DB" >"$CONF"
  ok "衰减参数已保存: SYS_DECAY_DB=$SYS_DECAY_DB（${CONF#$HOME/}）"
fi

step "4/4 校验"
if [ $DRY -eq 1 ]; then
  log "[dry-run] 跳过校验"
  exit 0
fi
n=0; bad=0
for e in "${EVENTS[@]}"; do
  n=$((n+1))
  [ -s "$STEREO/${e%%|*}.oga" ] || { warn "缺失或空文件: ${e%%|*}.oga"; bad=$((bad+1)); }
done
[ "$bad" -eq 0 ] || die "$bad 个事件音异常"
ok "$n/$n 个事件音就绪，当前主题: $(cur_theme)"
echo
log "试听: ./scripts/11-sound-theme.sh --preview"
log "回滚: ./scripts/11-sound-theme.sh --restore"
log "状态: ./scripts/99-verify.sh（美化段已含声音主题检查）"
