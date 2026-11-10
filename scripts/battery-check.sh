#!/usr/bin/env bash
# battery-check.sh — 电池 / 供电链路只读检测
# 注意（ISSUE-24）：提权失败必须显式告警，绝不能静默降级后把「读不到」当成「不存在」。
SUDO="sudo -n"
CAN_SUDO=1
$SUDO true 2>/dev/null || { CAN_SUDO=0; SUDO=""; }

echo "================ 电池与供电检测报告 ================"
if [ "$CAN_SUDO" -eq 0 ]; then
  echo '  !! 免密 sudo 不可用：dmidecode / dmesg 结果不完整，本报告不可作为结论依据'
fi
printf '时间: %s\n\n' "$(date '+%F %T')"

echo "---- 1. 机型与 BIOS ----"
printf '  产品: %s / %s\n' "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" "$(cat /sys/class/dmi/id/product_version 2>/dev/null)"
printf '  主板: %s   BIOS: %s %s\n' \
  "$(cat /sys/class/dmi/id/board_name 2>/dev/null)" \
  "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)" \
  "$(cat /sys/class/dmi/id/bios_date 2>/dev/null)"

echo; echo "---- 2. SMBIOS Type 22 (固件报告的电池) ----"
if command -v dmidecode >/dev/null 2>&1; then
  $SUDO dmidecode -t 22 2>/dev/null | sed -n '1,40p' | sed 's/^/  /'
else
  echo '  dmidecode 未安装'
fi

echo; echo "---- 3. sysfs power_supply ----"
for d in /sys/class/power_supply/*; do
  [ -d "$d" ] || continue
  echo "  [$(basename "$d")]"
  for k in type present status online capacity capacity_level health technology \
           model_name manufacturer serial_number cycle_count \
           voltage_now voltage_min_design power_now current_now \
           energy_full energy_full_design energy_now \
           charge_full charge_full_design charge_now \
           charge_start_threshold charge_stop_threshold; do
    [ -e "$d/$k" ] && printf '    %-24s %s\n' "$k" "$(cat "$d/$k" 2>/dev/null)"
  done
done

echo; echo "---- 4. 电池健康度 ----"
FOUND=0
for b in /sys/class/power_supply/BAT*; do
  [ -d "$b" ] || continue
  FOUND=1
  if [ -e "$b/energy_full" ]; then
    full=$(cat "$b/energy_full" 2>/dev/null); design=$(cat "$b/energy_full_design" 2>/dev/null); unit="Wh"
  else
    full=$(cat "$b/charge_full" 2>/dev/null); design=$(cat "$b/charge_full_design" 2>/dev/null); unit="Ah"
  fi
  if [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] 2>/dev/null; then
    awk -v n="$(basename "$b")" -v f="$full" -v d="$design" -v u="$unit" \
      'BEGIN{printf "  %s: %.2f %s / 设计 %.2f %s = 健康度 %.1f%%\n", n, f/1e6, u, d/1e6, u, f/d*100}'
  fi
done
[ $FOUND -eq 0 ] && echo '  未发现 BAT* 设备'

echo; echo "---- 5. upower ----"
upower -e 2>/dev/null | sed 's/^/  /'
upower -d 2>/dev/null | grep -iE 'battery|state:|percentage|capacity|energy|voltage|time to|vendor|model|power supply|online' \
  | head -40 | sed 's/^/  /'

echo; echo "---- 6. ACPI / thinkpad_acpi ----"
if command -v acpi >/dev/null 2>&1; then acpi -V 2>/dev/null | sed 's/^/  /'; else echo '  acpi 未安装 (sudo apt install -y acpi 可补)'; fi
cat /proc/acpi/ibm/battery 2>/dev/null | sed 's/^/  thinkpad: /'
lsmod 2>/dev/null | grep -E 'thinkpad_acpi|^battery|^ac ' | sed 's/^/  /'

echo; echo "---- 7. USB-C 适配器功率 ----"
for d in /sys/class/power_supply/ucsi-source-psy-*; do
  [ -d "$d" ] || continue
  v=$(cat "$d/voltage_now" 2>/dev/null); c=$(cat "$d/current_now" 2>/dev/null)
  if [ -n "$v" ] && [ -n "$c" ]; then
    awk -v n="$(basename "$d")" -v v="$v" -v c="$c" \
      'BEGIN{printf "  %-32s %.2f V x %.2f A = %.1f W\n", n, v/1e6, c/1e6, v*c/1e12}'
  fi
done

echo; echo "---- 8. 内核日志 (电池 / ACPI / EC) ----"
$SUDO dmesg 2>/dev/null | grep -iE 'battery|BAT[0-9]|acpi.*(error|exception|not found)|embedded controller|thinkpad_acpi|power_supply|ucsi|charger' \
  | tail -30 | sed 's/^/  /'

echo; echo "---- 9. 自动判断 ----"
T22=$($SUDO dmidecode -t 22 2>/dev/null)
if [ "$CAN_SUDO" -eq 0 ]; then
  echo '  [?] 无法判定：缺少 sudo，DMI 数据不可信。请配置免密 sudo 后重跑'
  echo '      （绝不能把「读不到」当成「没有电池」——ISSUE-05/24）'
elif [ $FOUND -eq 1 ]; then
  echo '  [OK] sysfs 检测到电池，健康度见第 4 节'
elif echo "$T22" | grep -qi 'portable battery'; then
  echo '  [!] 固件报告有电池但内核未创建 BAT* -> ACPI/驱动层问题，重点看第 8 节'
elif [ -z "$T22" ]; then
  echo '  [?] dmidecode 无输出 -> 检测失败，不能得出结论'
else
  echo '  [!] 固件无 Type 22 电池记录 -> 物理无电池，或 BIOS 中电池被禁用'
fi
echo "===================================================="
