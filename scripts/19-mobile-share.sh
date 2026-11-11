#!/usr/bin/env bash
# ============================================================================
# 19-mobile-share.sh - 把电脑文件「交给」手机上正在用的 App
#   scrcpy 的拖放只是把文件 push 到 /sdcard/Download/，不会交给任何 App；
#   Android 也没有通用的「拖放接收」接口。本脚本用 SEND intent 做等效：
#   push → 构造 content:// URI → 发给前台 App（拿不到前台就弹分享面板）
# 用法:
#   ./scripts/19-mobile-share.sh --share <文件>...     # 交给 App（推荐）
#   ./scripts/19-mobile-share.sh --share a.jpg --app wechat
#   ./scripts/19-mobile-share.sh --open /sdcard/Download/a.jpg   # 用默认 App 打开
#   ./scripts/19-mobile-share.sh --status
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/mobile.conf"
DEST_REMOTE="/sdcard/Download"
LAST_ADDR=""
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

ACTION=""
APP=""
TARGET=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --share|--open|--status) ACTION="${1#--}" ;;
    --app)
      APP="${2:-}"
      case "$APP" in
        wechat|wx) APP="com.tencent.mm" ;;
        qq)        APP="com.tencent.mobileqq" ;;
      esac
      shift ;;
    --to) TARGET="${2:-}"; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) die "未知参数: $1" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
[ -n "$ACTION" ] || { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

get_device() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator/ {print $1; exit}'
}

ensure_device() {
  DEV="$(get_device)"
  if [ -z "$DEV" ] && [ -n "$LAST_ADDR" ]; then
    log "当前无设备，尝试复用已保存地址 $LAST_ADDR"
    timeout 10 adb connect "$LAST_ADDR" >/dev/null 2>&1
    sleep 1
    DEV="$(get_device)"
  fi
  [ -n "$DEV" ] || die "没有已连接设备。先执行 ./scripts/mobile-connect.sh --status 诊断"
}

mime_of() {
  case "${1##*.}" in
    jpg|jpeg|png|gif|webp|bmp|heic|heif) echo 'image/*' ;;
    mp4|mkv|mov|avi|3gp|webm)            echo 'video/*' ;;
    mp3|wav|flac|m4a|aac|ogg|opus)       echo 'audio/*' ;;
    pdf)                                  echo 'application/pdf' ;;
    txt|md|log|csv|json|xml|conf)         echo 'text/plain' ;;
    apk)                                  echo 'application/vnd.android.package-archive' ;;
    zip|tar|gz|7z|xz)                     echo 'application/octet-stream' ;;
    *)                                    echo '*' ;;
  esac
}

# 手机当前前台包名；锁屏/息屏时返回空
front_pkg() {
  adb -s "$DEV" shell dumpsys window 2>/dev/null \
    | grep -m1 'mCurrentFocus' \
    | sed -nE 's/.*u0 ([a-zA-Z0-9._]+)\/.*/\1/p'
}

# /sdcard/Download/x.jpg -> content://.../document/primary%3ADownload%2Fx.jpg
doc_uri() {
  local p="${1#/sdcard/}"
  local enc
  enc="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote("primary:"+sys.argv[1], safe=""))' "$p")"
  echo "content://com.android.externalstorage.documents/document/$enc"
}

if [ "$ACTION" = status ]; then
  ensure_device
  echo "设备      : $DEV"
  echo "前台 App  : $(front_pkg || true)${APP:+（将直发 $APP）}"
  echo "推送目标  : ${TARGET:-$DEST_REMOTE}"
  echo "提示      : 手机锁屏时读不到前台 App，会退回系统分享面板"
  exit 0
fi

# ---- open：用手机默认 App 打开一个手机上的路径 ------------------------------
if [ "$ACTION" = open ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --open <手机路径>"
  ensure_device
  for p in "${ARGS[@]}"; do
    mime="$(mime_of "$p")"
    log "打开 $p（$mime）"
    adb -s "$DEV" shell am start -a android.intent.action.VIEW -d "$(doc_uri "$p")" -t "$mime" 2>&1 | tail -1
  done
  exit 0
fi

# ---- share：推送后交给 App --------------------------------------------------
if [ "$ACTION" = share ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --share <文件>..."
  ensure_device
  REMOTE="${TARGET:-$DEST_REMOTE}"
  adb -s "$DEV" shell mkdir -p "$REMOTE" >/dev/null 2>&1

  for f in "${ARGS[@]}"; do
    [ -e "$f" ] || { warn "跳过（不存在）: $f"; continue; }
    name="$(basename "$f")"
    mime="$(mime_of "$f")"
    remote="$REMOTE/$name"

    log "推送 $name → $REMOTE/"
    adb -s "$DEV" push "$f" "$REMOTE/" >/dev/null 2>&1 || { warn "推送失败: $f"; continue; }
    # 让媒体库索引，图片/视频才能被相册类应用读到
    adb -s "$DEV" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file://$remote" >/dev/null 2>&1 || true

    uri="$(doc_uri "$remote")"
    target_app="$APP"
    if [ -z "$target_app" ]; then
      target_app="$(front_pkg || true)"
      [ -n "$target_app" ] && log "检测到前台 App: $target_app"
    fi

    log "交给 App（$mime）"
    out=""
    if [ -n "$target_app" ]; then
      out="$(adb -s "$DEV" shell am start -a android.intent.action.SEND -t "$mime" \
        -p "$target_app" --eu android.intent.extra.STREAM "$uri" 2>&1)"
      case "$out" in
        *Error*|*Exception*)
          warn "直发 $target_app 失败，退回系统分享面板"
          out="$(adb -s "$DEV" shell am start -a android.intent.action.SEND -t "$mime" \
            --eu android.intent.extra.STREAM "$uri" 2>&1)"
          ;;
      esac
    else
      out="$(adb -s "$DEV" shell am start -a android.intent.action.SEND -t "$mime" \
        --eu android.intent.extra.STREAM "$uri" 2>&1)"
    fi

    case "$out" in
      *Starting*) ok "已在手机弹出：$name" ;;
      *)          warn "未启动: $(printf '%s' "$out" | tr -d '\r' | head -1)" ;;
    esac
  done
  echo
  log "手机上选择目标应用即可完成发送；下次可用 --app wechat 直达"
  exit 0
fi
