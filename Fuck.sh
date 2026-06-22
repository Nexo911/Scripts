#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="2026.06.22-final-3pass"
MODE="${1:-install}"
USER_NAME="${SUDO_USER:-${USER:-nexo77}}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
if [[ -z "$HOME_DIR" ]]; then
  HOME_DIR="$HOME"
fi

TS="$(date +%Y%m%d-%H%M%S)"
STATE_DIR="$HOME_DIR/.local/state/nexo77-hypr-final"
LOG_DIR="$STATE_DIR/logs"
CACHE_DIR="$HOME_DIR/.cache/nexo77-hypr-final"
BACKUP_DIR="$HOME_DIR/rice-backups/nexo77-hypr-final-$TS"
LOG_FILE="$LOG_DIR/$TS-$MODE.log"
REPORT_FILE="$STATE_DIR/last-report.txt"
HYPR_DIR="$HOME_DIR/.config/hypr"
HYPR_CONFIG_DIR="$HYPR_DIR/config"
LOCAL_BIN="$HOME_DIR/.local/bin"
WARNINGS=()

mkdir -p "$STATE_DIR" "$LOG_DIR" "$CACHE_DIR" "$HOME_DIR/rice-backups"
exec > >(tee -a "$LOG_FILE") 2>&1

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

say() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$BLUE" "$*" "$RESET"; }
ok() { printf '%s[+]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { WARNINGS+=("$*"); printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
die() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { printf '%s$%s ' "$BOLD" "$RESET"; printf '%q ' "$@"; printf '\n'; "$@"; }

banner() {
  cat <<BANNER
╔══════════════════════════════════════════════════════════════╗
║           NEXO77 HYPRLAND FINAL REPAIR                      ║
║           version: $SCRIPT_VERSION                          ║
╚══════════════════════════════════════════════════════════════╝
Mode: $MODE
User: $USER_NAME
Home: $HOME_DIR
Log : $LOG_FILE
BANNER
}

usage() {
  cat <<USAGE
Uso:
  bash ./nexo77_hyprland_final_repair.sh install   # reparación completa
  bash ./nexo77_hyprland_final_repair.sh runtime   # reinicia solo el runtime del rice
  bash ./nexo77_hyprland_final_repair.sh doctor    # diagnóstico
  bash ./nexo77_hyprland_final_repair.sh rollback  # restaura último backup
USAGE
}

preflight() {
  step "Preflight seguro"
  [[ "${EUID}" -eq 0 ]] && die "No ejecutes esta script como root/sudo. Ejecútala como usuario normal: $USER_NAME"
  [[ -d "$HOME_DIR" ]] || die "No existe HOME_DIR: $HOME_DIR"

  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
  else
    die "No existe /etc/os-release"
  fi

  case "${ID,,}" in
    arch|cachyos|endeavouros|manjaro|garuda|parch)
      ok "Sistema soportado: ${PRETTY_NAME:-$ID}"
      ;;
    *)
      die "Sistema no soportado: ${ID:-unknown}. Esto está pensado para Arch/CachyOS."
      ;;
  esac

  ok "Usuario: $USER_NAME"
  ok "Home: $HOME_DIR"
  run sudo -v
}

make_backup() {
  step "Backup antes de tocar nada"
  mkdir -p "$BACKUP_DIR"

  if [[ -d "$HYPR_DIR" ]]; then
    cp -a "$HYPR_DIR" "$BACKUP_DIR/hypr" || warn "No pude respaldar $HYPR_DIR"
  fi

  if [[ -d "$LOCAL_BIN" ]]; then
    cp -a "$LOCAL_BIN" "$BACKUP_DIR/local-bin" || warn "No pude respaldar $LOCAL_BIN"
  fi

  if [[ -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    sudo cp -a /usr/share/wayland-sessions/hyprland.desktop "$BACKUP_DIR/hyprland.desktop.system" || warn "No pude respaldar hyprland.desktop"
    sudo chown -R "$USER_NAME:$(id -gn "$USER_NAME")" "$BACKUP_DIR" 2>/dev/null || true
  fi

  ok "Backup guardado en: $BACKUP_DIR"
}

pkg_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

install_packages() {
  step "Instalar/verificar paquetes necesarios"
  local official_pkgs=(
    hyprland hypridle hyprlock sddm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    qt6-wayland qt6-declarative qt6-svg qt6-5compat qt6-multimedia qt6-websockets
    wl-clipboard cliphist jq psmisc playerctl swayosd brightnessctl pamixer dbus polkit
    kitty rofi-wayland git curl
  )

  local pkg
  for pkg in "${official_pkgs[@]}"; do
    if pkg_installed "$pkg"; then
      ok "OK paquete: $pkg"
    else
      if sudo pacman -S --needed --noconfirm "$pkg"; then
        ok "Instalado: $pkg"
      else
        warn "Falló paquete oficial: $pkg"
      fi
    fi
  done

  local aur_helper=""
  if have yay; then
    aur_helper="yay"
  elif have paru; then
    aur_helper="paru"
  fi

  local aur_pkgs=(quickshell-git awww)
  if [[ -n "$aur_helper" ]]; then
    for pkg in "${aur_pkgs[@]}"; do
      if pkg_installed "$pkg"; then
        ok "OK AUR: $pkg"
      else
        if "$aur_helper" -S --needed --noconfirm "$pkg"; then
          ok "Instalado AUR: $pkg"
        else
          warn "Falló AUR: $pkg"
        fi
      fi
    done
  else
    warn "No encontré yay/paru. Si falta el rice visual, instala luego: yay -S quickshell-git awww"
  fi
}

comment_dangerous_tty_autostarts() {
  step "Comentar autoarranques peligrosos de TTY"
  local files=(
    "$HOME_DIR/.zprofile"
    "$HOME_DIR/.profile"
    "$HOME_DIR/.bash_profile"
    "$HOME_DIR/.zlogin"
    "$HOME_DIR/.config/fish/config.fish"
  )

  local file
  for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    cp -a "$file" "$file.bak-nexo77-hypr-final-$TS" || true
    sed -i -E \
      -e '/^[[:space:]]*(exec[[:space:]]+)?Hyprland([[:space:]]|$)/ s/^/# DISABLED_BY_NEXO77_HYPR_FINAL /' \
      -e '/^[[:space:]]*(exec[[:space:]]+)?start-hyprland([[:space:]]|$)/ s/^/# DISABLED_BY_NEXO77_HYPR_FINAL /' \
      -e '/^[[:space:]]*(exec[[:space:]]+)?dbus-run-session[[:space:]]+Hyprland([[:space:]]|$)/ s/^/# DISABLED_BY_NEXO77_HYPR_FINAL /' \
      "$file" || warn "No pude parchear $file"
  done
  ok "Autoarranques peligrosos comentados si existían"
}

find_rice_source() {
  local candidates=(
    "$HOME_DIR/.cache/ilyamiro-rice-healer/imperative-dots/.config/hypr"
    "$HOME_DIR/.cache/ilyamiro-rice-rescue/imperative-dots/.config/hypr"
    "$HOME_DIR/imperative-dots/.config/hypr"
    "$HOME_DIR/dots-hyprland/.config/hypr"
    "$CACHE_DIR/imperative-dots/.config/hypr"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if have git; then
    step "No encontré cache del rice; clonando imperative-dots"
    rm -rf "$CACHE_DIR/imperative-dots"
    if git clone --depth 1 https://github.com/ilyamiro/imperative-dots "$CACHE_DIR/imperative-dots"; then
      if [[ -d "$CACHE_DIR/imperative-dots/.config/hypr" ]]; then
        printf '%s\n' "$CACHE_DIR/imperative-dots/.config/hypr"
        return 0
      fi
    else
      warn "No pude clonar imperative-dots. Usaré config mínima."
    fi
  else
    warn "git no existe. Usaré config mínima si no hay cache."
  fi

  return 1
}

deploy_rice_or_minimal() {
  step "Restaurar rice o crear configuración mínima"
  local source=""
  if source="$(find_rice_source)"; then
    ok "Fuente del rice: $source"
    rm -rf "$HYPR_DIR"
    mkdir -p "$(dirname "$HYPR_DIR")"
    cp -a "$source" "$HYPR_DIR" || die "No pude copiar rice desde $source"
  else
    warn "Sin fuente del rice. Creando configuración mínima estable."
    rm -rf "$HYPR_DIR"
    mkdir -p "$HYPR_CONFIG_DIR"
  fi

  mkdir -p "$HYPR_CONFIG_DIR" "$LOCAL_BIN"

  if [[ -d "$HYPR_DIR/scripts" ]]; then
    find "$HYPR_DIR/scripts" -type f -name '*.sh' -exec chmod +x {} \; || true
  fi
}

clean_bad_references() {
  step "Eliminar referencias malas y líneas incompatibles"
  rm -f "$HYPR_CONFIG_DIR/login-stable.conf" "$HYPR_CONFIG_DIR/rice-rescue.conf" 2>/dev/null || true
  rm -f "$LOCAL_BIN/ilyamiro-rice-healer" "$LOCAL_BIN/ilyamiro-rice-runtime-clean" "$LOCAL_BIN/ilyamiro-rice-runtime-safe" 2>/dev/null || true

  if [[ -d "$HYPR_DIR" ]]; then
    while IFS= read -r -d '' file; do
      sed -i \
        -e '/login-stable\.conf/d' \
        -e '/rice-rescue\.conf/d' \
        -e '/windowrulev2/d' \
        -e '/ilyamiro-rice-healer/d' \
        -e '/ilyamiro-rice-runtime-clean/d' \
        -e '/ilyamiro-rice-runtime-safe/d' \
        -e '/Main\.qml/d' \
        -e '/TopBar\.qml/d' \
        -e '/Floating\.qml/d' \
        "$file" || true
    done < <(find "$HYPR_DIR" -type f \( -name '*.conf' -o -name '*.sh' -o -name '*.json' \) -print0 2>/dev/null)
  fi

  ok "Referencias malas eliminadas"
}

ensure_settings_json_safe() {
  step "Sanear settings.json"
  local settings="$HYPR_DIR/settings.json"
  mkdir -p "$HYPR_DIR"

  if [[ ! -s "$settings" ]]; then
    cat > "$settings" <<'JSON'
{
  "openGuideAtStartup": false,
  "startup": []
}
JSON
    return 0
  fi

  if have jq; then
    local tmp
    tmp="$(mktemp)"
    if jq '.openGuideAtStartup=false | .startup=[]' "$settings" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$settings"
    else
      rm -f "$tmp"
      warn "settings.json no era JSON válido; lo reescribo mínimo"
      cat > "$settings" <<'JSON'
{
  "openGuideAtStartup": false,
  "startup": []
}
JSON
    fi
  fi
}

compile_templates_if_available() {
  step "Compilar templates si existe settings_watcher"
  local watcher="$HYPR_DIR/scripts/settings_watcher.sh"
  if [[ -f "$watcher" ]]; then
    chmod +x "$watcher" || true
    if bash "$watcher" --compile; then
      ok "Templates compilados"
    else
      warn "settings_watcher falló; continuaré y escribiré autostart limpio"
    fi
  else
    warn "No existe $watcher; usaré archivos limpios mínimos"
  fi
}

ensure_clean_hypr_files() {
  step "Asegurar archivos limpios de Hyprland"
  mkdir -p "$HYPR_CONFIG_DIR"

  cat > "$HYPR_DIR/hyprland.conf" <<'EOF_HYPRLAND'
# nexo77 stable Hyprland entrypoint
source = ~/.config/hypr/config/env.conf
source = ~/.config/hypr/config/monitors.conf
source = ~/.config/hypr/config/settings.conf
source = ~/.config/hypr/config/keybindings.conf
source = ~/.config/hypr/config/autostart.conf
EOF_HYPRLAND

  if [[ ! -s "$HYPR_CONFIG_DIR/env.conf" ]]; then
    cat > "$HYPR_CONFIG_DIR/env.conf" <<'EOF_ENV'
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = QT_QPA_PLATFORM,wayland
env = GDK_BACKEND,wayland,x11
env = MOZ_ENABLE_WAYLAND,1
EOF_ENV
  fi

  if [[ ! -s "$HYPR_CONFIG_DIR/monitors.conf" ]]; then
    cat > "$HYPR_CONFIG_DIR/monitors.conf" <<'EOF_MON'
monitor = , preferred, auto, 1
EOF_MON
  fi

  if [[ ! -s "$HYPR_CONFIG_DIR/settings.conf" ]]; then
    cat > "$HYPR_CONFIG_DIR/settings.conf" <<'EOF_SETTINGS'
input {
    kb_layout = us
    follow_mouse = 1
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
}

decoration {
    rounding = 10
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
EOF_SETTINGS
  fi

  if [[ ! -s "$HYPR_CONFIG_DIR/keybindings.conf" ]]; then
    cat > "$HYPR_CONFIG_DIR/keybindings.conf" <<'EOF_KEYS'
$mod = SUPER
bind = $mod, RETURN, exec, kitty
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, D, exec, rofi -show drun
bind = $mod, L, exec, hyprlock
EOF_KEYS
  fi
}

write_runtime() {
  step "Crear runtime seguro del rice"
  mkdir -p "$LOCAL_BIN"

  cat > "$LOCAL_BIN/nexo77-rice-runtime" <<'EOF_RUNTIME'
#!/usr/bin/env bash
set -u

export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1

LOG_DIR="$HOME/.local/state/nexo77-rice-runtime"
mkdir -p "$LOG_DIR"

pkill -x quickshell 2>/dev/null || true
pkill -x awww-daemon 2>/dev/null || true
pkill -x hypridle 2>/dev/null || true
pkill -x swayosd-server 2>/dev/null || true
pkill -x wl-paste 2>/dev/null || true
pkill -x playerctld 2>/dev/null || true

sleep 1

dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS >"$LOG_DIR/env-dbus.log" 2>&1 || true
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS >"$LOG_DIR/env-systemd.log" 2>&1 || true
systemctl --user start hyprpolkitagent.service >"$LOG_DIR/hyprpolkitagent.log" 2>&1 || true

if command -v awww-daemon >/dev/null 2>&1; then
  setsid awww-daemon >"$LOG_DIR/awww-daemon.log" 2>&1 &
fi

if command -v hypridle >/dev/null 2>&1; then
  setsid hypridle >"$LOG_DIR/hypridle.log" 2>&1 &
fi

if command -v swayosd-server >/dev/null 2>&1; then
  setsid swayosd-server --top-margin 0.9 --style "$HOME/.config/swayosd/style.css" >"$LOG_DIR/swayosd-server.log" 2>&1 &
fi

if command -v wl-paste >/dev/null 2>&1; then
  setsid wl-paste --type text --watch cliphist store >"$LOG_DIR/wl-paste-text.log" 2>&1 &
  setsid wl-paste --type image --watch cliphist store >"$LOG_DIR/wl-paste-image.log" 2>&1 &
fi

if command -v playerctld >/dev/null 2>&1; then
  setsid playerctld >"$LOG_DIR/playerctld.log" 2>&1 &
fi

sleep 1

if command -v quickshell >/dev/null 2>&1 && [[ -f "$HOME/.config/hypr/scripts/quickshell/Shell.qml" ]]; then
  setsid env QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=Hyprland quickshell -p "$HOME/.config/hypr/scripts/quickshell/Shell.qml" >"$LOG_DIR/quickshell.log" 2>&1 &
fi
EOF_RUNTIME

  chmod +x "$LOCAL_BIN/nexo77-rice-runtime"
  ok "Runtime creado: $LOCAL_BIN/nexo77-rice-runtime"
}

write_clean_autostart() {
  step "Crear autostart limpio"
  mkdir -p "$HYPR_CONFIG_DIR"
  cat > "$HYPR_CONFIG_DIR/autostart.conf" <<'EOF_AUTOSTART'
# nexo77 clean autostart
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
exec-once = systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
exec-once = ~/.local/bin/nexo77-rice-runtime
exec-once = ~/.config/hypr/scripts/settings_watcher.sh &
EOF_AUTOSTART
  ok "Autostart limpio escrito"
}

write_start_hyprland_wrapper() {
  step "Crear start-hyprland seguro"
  mkdir -p "$LOCAL_BIN"
  cat > "$LOCAL_BIN/start-hyprland" <<'EOF_START'
#!/usr/bin/env bash
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "Ya estás dentro de Hyprland; no abro otra sesión"
  echo "Para salir usa: hyprctl dispatch exit"
  exit 0
fi

export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1

exec Hyprland
EOF_START
  chmod +x "$LOCAL_BIN/start-hyprland"
  ok "Wrapper creado: $LOCAL_BIN/start-hyprland"
}

fix_sddm_login() {
  step "Arreglar SDDM/login"
  if ! pkg_installed sddm; then
    sudo pacman -S --needed --noconfirm sddm || warn "No pude instalar sddm"
  fi

  sudo rm -f /usr/share/wayland-sessions/hyprland-safe.desktop 2>/dev/null || true

  if [[ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]]; then
    sudo mv /usr/share/wayland-sessions/hyprland-uwsm.desktop "/usr/share/wayland-sessions/hyprland-uwsm.desktop.disabled-$TS" || warn "No pude deshabilitar hyprland-uwsm.desktop"
  fi

  sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<'EOF_DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland session
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF_DESKTOP

  sudo systemctl set-default graphical.target || warn "No pude setear graphical.target"
  sudo systemctl enable -f sddm.service || warn "No pude habilitar sddm.service"
  ok "SDDM/login configurado"
}

restart_runtime_if_inside_hyprland() {
  step "Reiniciar runtime si ya estás dentro de Hyprland"
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    "$LOCAL_BIN/nexo77-rice-runtime" || warn "Runtime falló"
    if have hyprctl; then
      hyprctl reload || warn "hyprctl reload falló"
    fi
  else
    ok "No estás dentro de Hyprland; runtime arrancará al iniciar sesión"
  fi
}

doctor() {
  step "Doctor/diagnóstico"
  {
    echo "NEXO77 HYPRLAND FINAL REPORT - $TS"
    echo "Version: $SCRIPT_VERSION"
    echo "Mode: $MODE"
    echo "User: $USER_NAME"
    echo "Home: $HOME_DIR"
    echo "Session: HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}; XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}; XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
    echo "Backup: ${BACKUP_DIR:-none}"
    echo "Log: $LOG_FILE"
    echo
    echo "Important files:"
    for file in \
      "$HYPR_DIR/hyprland.conf" \
      "$HYPR_CONFIG_DIR/env.conf" \
      "$HYPR_CONFIG_DIR/monitors.conf" \
      "$HYPR_CONFIG_DIR/settings.conf" \
      "$HYPR_CONFIG_DIR/keybindings.conf" \
      "$HYPR_CONFIG_DIR/autostart.conf" \
      "$LOCAL_BIN/nexo77-rice-runtime" \
      "$LOCAL_BIN/start-hyprland" \
      "/usr/share/wayland-sessions/hyprland.desktop"; do
      if [[ -e "$file" ]]; then
        echo "OK: $file"
      else
        echo "MISSING: $file"
      fi
    done
    echo
    echo "Bad references scan:"
    grep -RInE 'login-stable\.conf|rice-rescue\.conf|windowrulev2|ilyamiro-rice-healer|ilyamiro-rice-runtime-(clean|safe)|Main\.qml|TopBar\.qml|Floating\.qml' "$HYPR_DIR" "$LOCAL_BIN" 2>/dev/null || echo "No bad references found"
    echo
    echo "Processes:"
    pgrep -a -u "$USER_NAME" -f 'Hyprland|quickshell|awww-daemon|hypridle|swayosd-server|wl-paste|playerctld' || true
    echo
    echo "Autostart content:"
    sed -n '1,160p' "$HYPR_CONFIG_DIR/autostart.conf" 2>/dev/null || true
    echo
    echo "Warnings:"
    if [[ "${#WARNINGS[@]}" -eq 0 ]]; then
      echo "No warnings"
    else
      printf '%s\n' "${WARNINGS[@]}"
    fi
  } | tee "$REPORT_FILE"
  ok "Reporte guardado en: $REPORT_FILE"
}

rollback() {
  step "Rollback último backup"
  local latest
  latest="$(ls -dt "$HOME_DIR"/rice-backups/nexo77-hypr-final-* 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest" ]] || die "No encontré backups nexo77-hypr-final-*"

  warn "Restaurando backup: $latest"
  if [[ -d "$latest/hypr" ]]; then
    rm -rf "$HYPR_DIR"
    mkdir -p "$(dirname "$HYPR_DIR")"
    cp -a "$latest/hypr" "$HYPR_DIR"
    ok "Restaurado $HYPR_DIR"
  fi

  if [[ -d "$latest/local-bin" ]]; then
    mkdir -p "$LOCAL_BIN"
    cp -a "$latest/local-bin/." "$LOCAL_BIN/"
    ok "Restaurado $LOCAL_BIN"
  fi

  if [[ -f "$latest/hyprland.desktop.system" ]]; then
    sudo cp -a "$latest/hyprland.desktop.system" /usr/share/wayland-sessions/hyprland.desktop || warn "No pude restaurar hyprland.desktop"
  fi

  ok "Rollback completado. Reinicia sesión."
}

install_mode() {
  preflight
  make_backup
  install_packages
  comment_dangerous_tty_autostarts
  deploy_rice_or_minimal
  clean_bad_references
  ensure_settings_json_safe
  compile_templates_if_available
  clean_bad_references
  ensure_clean_hypr_files
  write_runtime
  write_clean_autostart
  clean_bad_references
  write_start_hyprland_wrapper
  fix_sddm_login
  restart_runtime_if_inside_hyprland
  doctor
  ok "Reparación completa. Siguiente paso recomendado: sudo reboot"
}

runtime_mode() {
  preflight
  write_runtime
  clean_bad_references
  write_clean_autostart
  restart_runtime_if_inside_hyprland
  doctor
}

main() {
  banner
  case "$MODE" in
    install)
      install_mode
      ;;
    runtime)
      runtime_mode
      ;;
    doctor)
      doctor
      ;;
    rollback)
      rollback
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      die "Modo desconocido: $MODE"
      ;;
  esac
}

main "$@"
