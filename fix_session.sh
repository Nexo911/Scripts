#!/usr/bin/env bash
set -Eeuo pipefail

echo "==> Arreglando sesión Hyprland..."

sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null <<'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland session
Exec=uwsm start -- hyprland
Type=Application
DesktopNames=Hyprland
DESKTOP
echo "[+] Desktop file arreglado"

sudo systemctl restart sddm
echo "[+] SDDM reiniciado"

echo "==> Recolectando logs de logout..."
LOGDIR="$HOME/nexo77-logout-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

journalctl -b0 --no-pager -n 300                    > "$LOGDIR/journal.log"
journalctl -b0 --no-pager -u sddm                   > "$LOGDIR/sddm.log"
journalctl -b0 --no-pager -u systemd-logind          > "$LOGDIR/logind.log"
journalctl -b0 --no-pager -u uwsm 2>/dev/null        > "$LOGDIR/uwsm.log" || true
cp ~/.config/hypr/hypridle.conf   "$LOGDIR/" 2>/dev/null || true
cp ~/.config/hypr/config/autostart.conf "$LOGDIR/" 2>/dev/null || true
systemctl --user status hypridle hyprlock 2>/dev/null > "$LOGDIR/hypridle-status.log" || true
last -n 20                                           > "$LOGDIR/last-logins.log"
loginctl list-sessions                               > "$LOGDIR/sessions.log" 2>/dev/null || true

echo "[+] Logs guardados en: $LOGDIR"
echo ""
echo "======================================"
echo " Listo. Ahora entra a SDDM y loguéate"
echo " Si te vuelve a sacar, pégame el contenido de:"
echo " $LOGDIR/logind.log"
echo "======================================"
