#!/usr/bin/env bash
set -Eeuo pipefail

# Safe MYX215A workflow.
# This script uses ADB only. It never calls fastboot and never writes
# preloader, nvram, nvdata, userdata, seccfg or proinfo.

usage() {
  cat <<'EOF'
Uso:
  ./myx_safe_automation.sh backup  [--serial SERIAL] [--output DIR]
  ./myx_safe_automation.sh full    [--serial SERIAL] [--output DIR]
  ./myx_safe_automation.sh debloat [--serial SERIAL] [--output DIR]

Condiciones:
  - Una sola MYX conectada por USB.
  - Pantalla encendida, iniciada y desbloqueada.
  - Wi-Fi desconectado durante la modificación.
  - El modo full necesita varios GB libres.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Falta la orden: $1"; }

MODE="${1:-}"
shift || true
case "$MODE" in backup|full|debloat) ;; *) usage; exit 2 ;; esac

SERIAL=""
OUTPUT="$(pwd)/myx_backups"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --serial) [ "$#" -ge 2 ] || die "--serial necesita un valor"; SERIAL="$2"; shift 2 ;;
    --output) [ "$#" -ge 2 ] || die "--output necesita un valor"; OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
done

need adb
need awk
need date
need sha256sum
need stat

mapfile -t DEVICES < <(adb devices | awk '$2 == "device" {print $1}')
if [ -z "$SERIAL" ]; then
  [ "${#DEVICES[@]}" -eq 1 ] || die "Debe haber exactamente una MYX conectada; use --serial SERIAL"
  SERIAL="${DEVICES[0]}"
else
  printf '%s\n' "${DEVICES[@]}" | grep -Fxq "$SERIAL" || die "El dispositivo $SERIAL no está conectado como device"
fi

ADB=(adb -s "$SERIAL")

read_prop() { "${ADB[@]}" shell getprop "$1" | tr -d '\r'; }
wait_device() { "${ADB[@]}" wait-for-device; sleep 1; }

MODEL="$(read_prop ro.product.model)"
BUILD="$(read_prop ro.build.display.id)"
ANDROID="$(read_prop ro.build.version.release)"
ABI="$(read_prop ro.product.cpu.abilist)"
[ "$MODEL" = "MYX215A" ] || die "Modelo inesperado: $MODEL"

echo "Dispositivo: $SERIAL"
echo "Modelo:     $MODEL"
echo "Build:      $BUILD"
echo "Android:    $ANDROID"
echo "ABI:        $ABI"
case "$ANDROID" in 8.1*|8.0*) ;; *) die "Android no esperado: $ANDROID" ;; esac

if [ "$MODE" = "debloat" ]; then
  read -r -p "Confirma: pantalla encendida, desbloqueada y Wi-Fi desconectado [s/N]: " OK
  [[ "$OK" =~ ^[sS]$ ]] || die "Cancelado"
fi

"${ADB[@]}" root >/dev/null
wait_device
ID_OUT="$("${ADB[@]}" shell id)"
echo "$ID_OUT" | grep -q 'uid=0(root)' || die "ADB root no disponible"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$OUTPUT/${SERIAL}_${STAMP}"
mkdir -p "$DEST/apks" "$DEST/policy" "$DEST/partitions"

backup_small() {
  echo "Guardando respaldo pequeño en: $DEST"
  "${ADB[@]}" pull /system/priv-app/MDMMYX/MDMMYX.apk "$DEST/apks/MDMMYX.apk"
  "${ADB[@]}" pull /data/system/device_owner_2.xml "$DEST/policy/device_owner_2.xml"
  "${ADB[@]}" pull /data/system/device_policies.xml "$DEST/policy/device_policies.xml"
  "${ADB[@]}" pull /data/system/users/0.xml "$DEST/policy/user_0.xml"
  "${ADB[@]}" shell dumpsys device_policy > "$DEST/policy/device_policy.txt"
  {
    echo "serial=$SERIAL"
    echo "model=$MODEL"
    echo "build=$BUILD"
    echo "android=$ANDROID"
    echo "abi=$ABI"
  } > "$DEST/device_info.txt"
}

backup_full() {
  local by_name names name remote_size out_size
  by_name="$("${ADB[@]}" shell 'find /dev/block/platform -type d -name by-name -print -quit' | tr -d '\r')"
  [ -n "$by_name" ] || die "No se encontró /dev/block/.../by-name"
  echo "by-name: $by_name"
  "${ADB[@]}" shell "ls -l '$by_name'" > "$DEST/partition_map.txt"
  names="$("${ADB[@]}" shell "ls -1 '$by_name'" | tr -d '\r')"
  printf '%s\n' "$names" > "$DEST/partition_names.txt"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in userdata|rpmb) echo "Omitiendo $name"; continue ;; esac
    remote_size="$("${ADB[@]}" shell blockdev --getsize64 "$by_name/$name" | tr -d '\r')"
    [[ "$remote_size" =~ ^[0-9]+$ ]] || die "Tamaño inválido para $name"
    echo "Leyendo $name ($remote_size bytes)..."
    "${ADB[@]}" exec-out "dd if='$by_name/$name' bs=1048576 2>/dev/null" > "$DEST/partitions/$name.img"
    out_size="$(stat -c '%s' "$DEST/partitions/$name.img")"
    [ "$out_size" = "$remote_size" ] || die "$name incompleta: esperado $remote_size, obtenido $out_size"
    echo "OK: $name $out_size bytes"
  done <<< "$names"
  (cd "$DEST" && sha256sum partitions/*.img) > "$DEST/SHA256SUMS"
}

disable_mdm() {
  "${ADB[@]}" disable-verity
  "${ADB[@]}" reboot
  wait_device
  "${ADB[@]}" root >/dev/null
  wait_device
  "${ADB[@]}" remount | tee "$DEST/remount.txt"
  grep -q 'remount succeeded' "$DEST/remount.txt" || die "remount no confirmado"
  "${ADB[@]}" shell 'set -e
cp -p /system/priv-app/MDMMYX/MDMMYX.apk /data/local/tmp/MDMMYX.apk.original
mv /system/priv-app/MDMMYX/MDMMYX.apk /system/priv-app/MDMMYX/MDMMYX.apk.disabled
sync'
  "${ADB[@]}" reboot
  wait_device
  "${ADB[@]}" root >/dev/null
  wait_device
}

clear_policy() {
  local tmp
  tmp="$(mktemp -d)"
  cat > "$tmp/device_owner_2.xml" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<root />
EOF
  cat > "$tmp/device_policies.xml" <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<policies setup-complete="true" provisioning-state="0" />
EOF
  "${ADB[@]}" push "$tmp/device_owner_2.xml" /data/local/tmp/device_owner_2.new.xml >/dev/null
  "${ADB[@]}" push "$tmp/device_policies.xml" /data/local/tmp/device_policies.new.xml >/dev/null
  "${ADB[@]}" shell 'set -e
cp /data/local/tmp/device_owner_2.new.xml /data/system/device_owner_2.xml
cp /data/local/tmp/device_policies.new.xml /data/system/device_policies.xml
chown system:system /data/system/device_owner_2.xml
chown system:system /data/system/device_policies.xml
chmod 600 /data/system/device_owner_2.xml
chmod 600 /data/system/device_policies.xml
sync'
  rm -rf "$tmp"
}

case "$MODE" in
  backup)
    backup_small
    ;;
  full)
    backup_small
    backup_full
    ;;
  debloat)
    backup_small
    disable_mdm
    clear_policy
    "${ADB[@]}" reboot
    wait_device
    "${ADB[@]}" root >/dev/null
    wait_device
    "${ADB[@]}" shell dumpsys device_policy > "$DEST/device_policy_after.txt"
    "${ADB[@]}" shell dumpsys activity activities > "$DEST/activity_after.txt"
    echo "Modificación terminada. Revisa: $DEST"
    ;;
esac

echo "Completado: $DEST"
