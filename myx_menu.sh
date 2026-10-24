#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW="$BASE/myx_safe_automation.sh"
BACKUPS="$BASE/backups"

command -v adb >/dev/null 2>&1 || { echo "ERROR: adb no está instalado."; exit 1; }
[ -x "$WORKFLOW" ] || { echo "ERROR: falta myx_safe_automation.sh."; exit 1; }

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_CYAN=$'\033[1;36m'
  C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
else
  C_RESET=''; C_BLUE=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''
fi

mapfile -t DEVICES < <(adb devices | awk '$2 == "device" {print $1}')
[ "${#DEVICES[@]}" -gt 0 ] || {
  echo "${C_RED}No hay una MYX conectada por USB.${C_RESET}"; exit 1;
}

if [ "${#DEVICES[@]}" -eq 1 ]; then
  SERIAL="${DEVICES[0]}"
else
  echo "Hay varias MYX conectadas. Selecciona una:"
  select SERIAL in "${DEVICES[@]}"; do
    [ -n "${SERIAL:-}" ] && break
  done
fi

ADB=(adb -s "$SERIAL")
MODEL=$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')
BUILD=$("${ADB[@]}" shell getprop ro.build.display.id | tr -d '\r')
ANDROID=$("${ADB[@]}" shell getprop ro.build.version.release | tr -d '\r')

pause_menu() { read -r -p $'\nPulsa Enter para volver al menú...' _; }
confirm() {
  local answer
  read -r -p "$1 [s/N]: " answer
  [[ "$answer" =~ ^[sS]$ ]]
}
run_workflow() {
  mkdir -p "$BACKUPS"
  "$WORKFLOW" "$1" --serial "$SERIAL" --output "$BACKUPS"
}

while true; do
  clear || true
  echo "${C_BLUE}╔══════════════════════════════════════════════╗${C_RESET}"
  echo "${C_BLUE}║${C_RESET}        ${C_CYAN}MYX215A SAFE TOOL${C_RESET}                 ${C_BLUE}║${C_RESET}"
  echo "${C_BLUE}║${C_RESET}  Respaldo y eliminación reversible del MDM  ${C_BLUE}║${C_RESET}"
  echo "${C_BLUE}╚══════════════════════════════════════════════╝${C_RESET}"
  echo
  echo "${C_GREEN}Dispositivo:${C_RESET} $SERIAL"
  echo "${C_GREEN}Modelo:${C_RESET}      $MODEL"
  echo "${C_GREEN}Android:${C_RESET}     $ANDROID"
  echo "${C_GREEN}Build:${C_RESET}       $BUILD"
  echo
  echo "${C_CYAN} 1 ${C_RESET} Respaldo pequeño (MDM y políticas)"
  echo "${C_CYAN} 2 ${C_RESET} Respaldo completo de particiones"
  echo "${C_YELLOW} 3 ${C_RESET} Quitar login/MDM de forma reversible"
  echo "${C_CYAN} 4 ${C_RESET} Verificar estado"
  echo "${C_CYAN} 5 ${C_RESET} Volver a detectar dispositivo"
  echo "${C_RED} 0 ${C_RESET} Salir"
  echo
  read -r -p "Selecciona una opción: " OPTION

  case "$OPTION" in
    1) run_workflow backup; pause_menu ;;
    2)
      if confirm "El respaldo completo necesita varios GB libres. ¿Continuar?"; then
        run_workflow full
      fi
      pause_menu
      ;;
    3)
      echo
      echo "${C_YELLOW}La pantalla debe estar encendida, desbloqueada y sin Wi-Fi.${C_RESET}"
      echo "No se usará fastboot ni se tocarán NVRAM/NVDATA."
      if confirm "¿Confirmas modificar esta MYX?"; then run_workflow debloat; fi
      pause_menu
      ;;
    4)
      echo
      "${ADB[@]}" shell id
      echo
      echo "MDM:"
      "${ADB[@]}" shell pm path com.abupdate.mdm || true
      echo
      echo "Device Owner/políticas:"
      "${ADB[@]}" shell dumpsys device_policy \
        | grep -E 'Device Owner|admin=|package=|lock-task|statusbar' || true
      pause_menu
      ;;
    5) exec "$0" ;;
    0) exit 0 ;;
    *) echo "${C_RED}Opción no válida.${C_RESET}"; sleep 1 ;;
  esac
done
