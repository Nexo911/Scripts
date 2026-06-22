#!/usr/bin/env bash
# Hyprland fix for 67 errors and broken configs
# This script attempts to reset the Hyprland configuration to a clean state
# and remove deprecated or problematic configuration files. It backs up the
# existing configuration before making changes. Run this as your normal
# user (not as root) in TTY or a terminal session.

set -euo pipefail

# Bail out if run as root
if [[ "${EUID}" -eq 0 ]]; then
    echo "Por seguridad, no ejecute este script como root. Use su usuario normal."
    exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/rice-backups/hyprland-fix-${TS}"
CONFIG_DIR="$HOME/.config/hypr"
LOCAL_BIN="$HOME/.local/bin"

mkdir -p "$BACKUP_DIR"

# Backup existing configuration and scripts
if [[ -d "$CONFIG_DIR" ]]; then
    cp -a "$CONFIG_DIR" "$BACKUP_DIR/hypr"
fi
if [[ -d "$LOCAL_BIN" ]]; then
    cp -a "$LOCAL_BIN" "$BACKUP_DIR/local-bin"
fi

echo "Configuración actual respaldada en: $BACKUP_DIR"

# Remove problematic files and deprecated configs
rm -f "$CONFIG_DIR/config/login-stable.conf" || true
rm -f "$CONFIG_DIR/config/rice-rescue.conf" || true
rm -f "$LOCAL_BIN/ilyamiro-rice-healer" || true
rm -f "$LOCAL_BIN/ilyamiro-rice-runtime-clean" || true
rm -f "$LOCAL_BIN/ilyamiro-rice-runtime-safe" || true

# Clean references in main hyprland.conf and autostart.conf
if [[ -f "$CONFIG_DIR/hyprland.conf" ]]; then
    sed -i '/login-stable.conf/d' "$CONFIG_DIR/hyprland.conf"
    sed -i '/rice-rescue.conf/d' "$CONFIG_DIR/hyprland.conf"
    sed -i '/windowrulev2/d' "$CONFIG_DIR/hyprland.conf"
fi
if [[ -f "$CONFIG_DIR/config/autostart.conf" ]]; then
    sed -i '/ilyamiro-rice-healer/d' "$CONFIG_DIR/config/autostart.conf"
    sed -i '/ilyamiro-rice-runtime/d' "$CONFIG_DIR/config/autostart.conf"
fi

# Kill leftover processes to prevent duplicates
pkill -x quickshell 2>/dev/null || true
pkill -x awww-daemon 2>/dev/null || true
pkill -x hypridle 2>/dev/null || true
pkill -x swayosd-server 2>/dev/null || true
pkill -x wl-paste 2>/dev/null || true
pkill -x playerctld 2>/dev/null || true

# Decide on source for fresh configuration
SOURCE_HYPR=""
# Prefer existing cached repo from previous installs
if [[ -d "$HOME/.cache/ilyamiro-rice-healer/imperative-dots/.config/hypr" ]]; then
    SOURCE_HYPR="$HOME/.cache/ilyamiro-rice-healer/imperative-dots/.config/hypr"
elif [[ -d "$HOME/.cache/ilyamiro-rice-rescue/imperative-dots/.config/hypr" ]]; then
    SOURCE_HYPR="$HOME/.cache/ilyamiro-rice-rescue/imperative-dots/.config/hypr"i

if [[ -n "$SOURCE_HYPR" ]]; then
    echo "Copiando configuración de '$SOURCE_HYPR'..."
    rm -rf "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    cp -a "$SOURCE_HYPR"/* "$CONFIG_DIR/"
else
    echo "No se encontró repositorio de configuración. Usando configuración mínima."
    rm -rf "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/config"

    # Minimal hyprland.conf
    cat > "$CONFIG_DIR/hyprland.conf" <<'EOF'
source = ~/.config/hypr/config/env.conf
source = ~/.config/hypr/config/monitors.conf
source = ~/.config/hypr/config/settings.conf
source = ~/.config/hypr/config/keybindings.conf
source = ~/.config/hypr/config/autostart.conf
EOF

    # Minimal environment variables
    cat > "$CONFIG_DIR/config/env.conf" <<'EOF'
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = QT_QPA_PLATFORM,wayland
env = GDK_BACKEND,wayland,x11
env = MOZ_ENABLE_WAYLAND,1
EOF

    # Minimal monitor configuration (auto-detect and scale)
    echo 'monitor = , preferred, auto, 1' > "$CONFIG_DIR/config/monitors.conf"

    # Minimal settings
    cat > "$CONFIG_DIR/config/settings.conf" <<'EOF'
input {
    kb_layout = us
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
EOF

    # Minimal keybindings
    cat > "$CONFIG_DIR/config/keybindings.conf" <<'EOF'
$mod = SUPER
bind = $mod, RETURN, exec, kitty
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, D, exec, rofi -show drun
EOF

    # Minimal autostart
    cat > "$CONFIG_DIR/config/autostart.conf" <<'EOF'
exec-once = awww-daemon
exec-once = hypridle
exec-once = quickshell -p ~/.config/hypr/scripts/quickshell/Shell.qml
exec-once = swayosd-server --top-margin 0.9 --style "$HOME/.config/swayosd/style.css"
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
EOF
fi

# Mark scripts executable
if [[ -d "$CONFIG_DIR/scripts" ]]; then
    find "$CONFIG_DIR/scripts" -type f -name '*.sh' -exec chmod +x {} \;
fi

# Compile settings if settings_watcher is available
if [[ -x "$CONFIG_DIR/scripts/settings_watcher.sh" ]]; then
    echo "Compilando plantillas con settings_watcher.sh..."
    "$CONFIG_DIR/scripts/settings_watcher.sh" --compile || true
fi

# Provide summary
cat <<'SUMMARY'
Se han eliminado configuraciones conflictivas y se ha restaurado una configuración limpia de Hyprland. Si tienes las plantillas de ilyamiro en ~/.cache, se han copiado automáticamente. Para usarla:

1. Sal de Hyprland con:
   hyprctl dispatch exit

2. En el login manager (SDDM), selecciona la sesión **Hyprland** y vuelve a iniciar.

3. Si no estás usando SDDM, ejecuta `Hyprland` desde tu TTY.

Si deseas volver al estado anterior, tu configuración antigua está en la carpeta:
  $BACKUP_DIR

¡Éxito!
SUMMARY

