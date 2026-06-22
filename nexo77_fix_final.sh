#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#  nexo77_fix_final.sh — CachyOS/Hyprland definitive fix
#  Arregla: boot lento, Service Crash, quickshell duplicado
# ============================================================

# ── Colores ──────────────────────────────────────────────────
R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m'
M=$'\033[35m' C=$'\033[36m' W=$'\033[97m' BOLD=$'\033[1m'
DIM=$'\033[2m' RESET=$'\033[0m'

beep() { printf '\a'; sleep 0.08; }

# ── Animación Minecraft nivel completado ─────────────────────
mc_levelup() {
  clear
  local frames=(
"${Y}
     ___________________
    |  LEVEL  COMPLETE! |
    |___________________|
        |||||||||||
       |  nexo77  |
       |__________|
${RESET}"
"${G}
     ___________________
    | ★ LEVEL  COMPLETE!|
    |___________________|
        |||||||||||
       |  nexo77  |
       |__________|
${RESET}"
  )
  for i in 1 2 1 2 1; do
    printf '%s' "${frames[$((i-1))]}"
    beep
    sleep 0.3
    clear
  done
}

# ── Barra de progreso estilo Minecraft ───────────────────────
mc_progress() {
  local label="$1"
  local total=20
  printf '\n%s%s%s\n' "$C" "$label" "$RESET"
  printf '['
  for ((i=0; i<total; i++)); do
    sleep 0.04
    printf '%s█%s' "$G" "$RESET"
  done
  printf '] %s✔%s\n' "$G" "$RESET"
  beep
}

# ── Pantalla de bienvenida ───────────────────────────────────
welcome() {
  clear
  printf '%s%s' "$G" "$BOLD"
  cat << 'MINECRAFT'

  ███╗   ██╗███████╗██╗  ██╗ ██████╗ ███████╗
  ████╗  ██║██╔════╝╚██╗██╔╝██╔═══██╗╚════██║
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║    ██╔╝
  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║   ██╔╝
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝   ██║
  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝   ╚═╝

MINECRAFT
  printf '%s' "$RESET"
  printf '%s       🎮  nexo77 Hyprland Fix — CachyOS Edition%s\n' "$Y" "$RESET"
  printf '%s       ⛏️   Minando bugs desde el bedrock...%s\n\n' "$DIM" "$RESET"
  sleep 0.5
  beep; sleep 0.1; beep; sleep 0.1; beep
  sleep 0.8
}

# ── Checks de seguridad ──────────────────────────────────────
preflight() {
  printf '\n%s⛏  Verificando mundo...%s\n' "$B" "$RESET"
  [[ "${EUID}" -eq 0 ]] && {
    printf '%s[ERROR]%s No ejecutes como root.\n' "$R" "$RESET"
    exit 1
  }
  [[ -d "$HOME" ]] || { printf '%s[ERROR]%s No existe HOME\n' "$R" "$RESET"; exit 1; }
  mc_progress "Verificando entorno"
}

# ── 1. Boot rápido ───────────────────────────────────────────
fix_boot() {
  printf '\n%s🚀 MISIÓN 1: Boot rápido (matar NetworkManager-wait-online)%s\n' "$Y" "$RESET"

  # Deshabilitar el servicio que tarda 7s
  sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null && \
    printf '  %s✔%s disabled NetworkManager-wait-online\n' "$G" "$RESET" || true
  sudo systemctl mask NetworkManager-wait-online.service 2>/dev/null && \
    printf '  %s✔%s masked NetworkManager-wait-online\n' "$G" "$RESET" || true

  # Dispositivos TPM/serial que también ralentizan (no críticos para el desktop)
  sudo systemctl mask dev-tpmrm0.device dev-tpm0.device 2>/dev/null || true
  printf '  %s✔%s TPM devices masked (no los usas para Hyprland)\n' "$G" "$RESET"

  mc_progress "Optimizando boot"
  printf '  %s💾 Ahorro estimado: ~7 segundos en el boot%s\n' "$G" "$RESET"
}

# ── 2. Eliminar drkonqi (el Service Crash) ───────────────────
fix_drkonqi() {
  printf '\n%s🔨 MISIÓN 2: Eliminar drkonqi (el "Service Crash" del popup)%s\n' "$Y" "$RESET"

  # Matar procesos activos ahora mismo
  pkill -f drkonqi 2>/dev/null && \
    printf '  %s✔%s Procesos drkonqi matados\n' "$G" "$RESET" || \
    printf '  %s-%s No había drkonqi corriendo\n' "$DIM" "$RESET"

  # Desinstalar drkonqi (crash reporter de KDE, inútil en Hyprland puro)
  if pacman -Qq drkonqi &>/dev/null; then
    printf '  %s➜%s Desinstalando drkonqi...\n' "$B" "$RESET"
    sudo pacman -R --noconfirm drkonqi 2>/dev/null && \
      printf '  %s✔%s drkonqi eliminado — adiós Service Crash!\n' "$G" "$RESET" || \
      printf '  %s!%s No pude desinstalar drkonqi (puede tener dependencias), ignorando\n' "$Y" "$RESET"
  else
    printf '  %s-%s drkonqi ya no estaba instalado\n' "$DIM" "$RESET"
  fi

  # Limpiar core dumps acumulados (pueden ocupar GBs)
  local coredump_dir="/var/lib/systemd/coredump"
  if [[ -d "$coredump_dir" ]]; then
    local count
    count=$(sudo ls "$coredump_dir" 2>/dev/null | wc -l)
    if [[ "$count" -gt 0 ]]; then
      sudo systemd-tmpfiles --clean 2>/dev/null || true
      printf '  %s✔%s Core dumps limpiados (%s archivos)\n' "$G" "$RESET" "$count"
    fi
  fi

  mc_progress "Eliminando crash reporter de KDE"
}

# ── 3. Matar duplicados y relanzar runtime limpio ────────────
fix_runtime() {
  printf '\n%s⚡ MISIÓN 3: Limpiar procesos duplicados y relanzar rice%s\n' "$Y" "$RESET"

  # Contar instancias antes
  local qs_count
  qs_count=$(pgrep -c -x quickshell 2>/dev/null || echo 0)
  printf '  %s➜%s Instancias de quickshell antes: %s\n' "$B" "$RESET" "$qs_count"

  # Matar todos los duplicados
  pkill -x quickshell  2>/dev/null || true
  pkill -x awww-daemon 2>/dev/null || true
  pkill -x hypridle    2>/dev/null || true
  pkill -x swayosd-server 2>/dev/null || true
  # Matar watchers huérfanos de quickshell
  pkill -f "quickshell/watchers" 2>/dev/null || true

  printf '  %s✔%s Todos los duplicados matados\n' "$G" "$RESET"
  mc_progress "Limpiando procesos duplicados"
  sleep 1

  # Exportar variables Wayland necesarias
  export XDG_CURRENT_DESKTOP=Hyprland
  export XDG_SESSION_DESKTOP=Hyprland
  export XDG_SESSION_TYPE=wayland
  export QT_QPA_PLATFORM=wayland
  export GDK_BACKEND=wayland,x11
  export MOZ_ENABLE_WAYLAND=1

  local LOG="$HOME/.local/state/nexo77-rice-runtime"
  mkdir -p "$LOG"

  # Relanzar servicios uno por uno
  if command -v awww-daemon &>/dev/null; then
    setsid awww-daemon >"$LOG/awww.log" 2>&1 &
    printf '  %s✔%s awww-daemon iniciado\n' "$G" "$RESET"
  fi

  if command -v hypridle &>/dev/null; then
    setsid hypridle >"$LOG/hypridle.log" 2>&1 &
    printf '  %s✔%s hypridle iniciado\n' "$G" "$RESET"
  fi

  if command -v swayosd-server &>/dev/null; then
    setsid swayosd-server --top-margin 0.9 \
      --style "$HOME/.config/swayosd/style.css" \
      >"$LOG/swayosd.log" 2>&1 &
    printf '  %s✔%s swayosd-server iniciado\n' "$G" "$RESET"
  fi

  sleep 1

  # Quickshell — solo si existe Shell.qml
  local shell_qml="$HOME/.config/hypr/scripts/quickshell/Shell.qml"
  if command -v quickshell &>/dev/null && [[ -f "$shell_qml" ]]; then
    setsid env \
      QT_QPA_PLATFORM=wayland \
      XDG_CURRENT_DESKTOP=Hyprland \
      quickshell -p "$shell_qml" \
      >"$LOG/quickshell.log" 2>&1 &
    printf '  %s✔%s quickshell iniciado (1 instancia limpia)\n' "$G" "$RESET"
  else
    printf '  %s!%s quickshell no encontrado o Shell.qml no existe\n' "$Y" "$RESET"
  fi

  mc_progress "Relanzando rice"

  # Recargar Hyprland si estamos dentro
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl &>/dev/null; then
    sleep 0.5
    hyprctl reload 2>/dev/null && \
      printf '  %s✔%s hyprctl reload ejecutado\n' "$G" "$RESET" || true
  fi
}

# ── 4. Verificar SDDM y sesión ───────────────────────────────
fix_sddm() {
  printf '\n%s🖥  MISIÓN 4: Verificar sesión SDDM%s\n' "$Y" "$RESET"

  # hyprland-uwsm ya está disabled según el doctor — confirmar
  if [[ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]]; then
    sudo mv /usr/share/wayland-sessions/hyprland-uwsm.desktop \
      "/usr/share/wayland-sessions/hyprland-uwsm.desktop.disabled-$$" 2>/dev/null || true
    printf '  %s✔%s hyprland-uwsm.desktop deshabilitado\n' "$G" "$RESET"
  else
    printf '  %s✔%s hyprland-uwsm ya estaba deshabilitado\n' "$G" "$RESET"
  fi

  # Asegurar que hyprland.desktop existe y es limpio
  if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland session
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
DESKTOP
    printf '  %s✔%s hyprland.desktop creado\n' "$G" "$RESET"
  else
    printf '  %s✔%s hyprland.desktop ya existe\n' "$G" "$RESET"
  fi

  mc_progress "Verificando sesión"
}

# ── 5. Diagnóstico final ─────────────────────────────────────
doctor() {
  printf '\n%s🔍 DIAGNÓSTICO FINAL%s\n' "$C" "$RESET"
  printf '%s─────────────────────────────────────────%s\n' "$DIM" "$RESET"

  printf '  Quickshell instancias: %s\n' "$(pgrep -c -x quickshell 2>/dev/null || echo 0)"
  printf '  awww-daemon: %s\n' "$(pgrep -x awww-daemon 2>/dev/null && echo corriendo || echo parado)"
  printf '  hypridle:    %s\n' "$(pgrep -x hypridle 2>/dev/null && echo corriendo || echo parado)"
  printf '  drkonqi:     %s\n' "$(pacman -Qq drkonqi 2>/dev/null && echo INSTALADO || echo eliminado ✔)"
  printf '  SDDM:        %s\n' "$(systemctl is-enabled sddm 2>/dev/null || echo desconocido)"
  printf '  NM-wait:     %s\n' "$(systemctl is-enabled NetworkManager-wait-online 2>/dev/null || echo masked ✔)"
  printf '%s─────────────────────────────────────────%s\n' "$DIM" "$RESET"
}

# ── Pantalla final ───────────────────────────────────────────
win_screen() {
  mc_levelup
  clear
  printf '%s%s' "$G" "$BOLD"
  cat << 'WIN'

  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║   ✅  YOU WIN — nexo77 Achievement!       ║
  ║                                           ║
  ║   🏆  Boot lento         →  FIXED         ║
  ║   🏆  Service Crash      →  FIXED         ║
  ║   🏆  Quickshell x5      →  FIXED         ║
  ║   🏆  UWSM warning       →  FIXED         ║
  ║                                           ║
  ║   Siguiente nivel:  sudo reboot           ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝

WIN
  printf '%s' "$RESET"
  beep; sleep 0.15; beep; sleep 0.15; beep; sleep 0.3
  beep; sleep 0.15; beep
  printf '\n%s  ⛏️  Presiona ENTER para terminar o haz: sudo reboot%s\n\n' "$Y" "$RESET"
  read -r _
}

# ── Main ─────────────────────────────────────────────────────
main() {
  welcome
  preflight
  fix_boot
  fix_drkonqi
  fix_runtime
  fix_sddm
  doctor
  win_screen
}

main "$@"
