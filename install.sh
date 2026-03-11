#!/bin/bash
#
# Raspberry Pi Kiosk Installer
# Für Debian 13 mit labwc (Wayland Compositor)
#
# Verwendung: sudo ./install.sh [KIOSK_URL]
# Beispiel:   sudo ./install.sh https://example.com/dashboard
#

set -e

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Standard-URL (Platzhalter)
DEFAULT_URL="https://www.deineurl.ch/hiereingeben"
KIOSK_URL="${1:-$DEFAULT_URL}"

# Benutzer für Kiosk (aktueller Benutzer oder Standard)
KIOSK_USER="${SUDO_USER:-pi}"
KIOSK_HOME="/home/$KIOSK_USER"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Raspberry Pi Kiosk Installer${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Sudo-Check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Fehler: Dieses Skript muss mit sudo ausgeführt werden!${NC}"
    echo "Verwendung: sudo $0 [KIOSK_URL]"
    exit 1
fi

echo -e "${YELLOW}Konfiguration:${NC}"
echo "  Kiosk-URL:    $KIOSK_URL"
echo "  Benutzer:     $KIOSK_USER"
echo "  Home-Pfad:    $KIOSK_HOME"
echo ""

# Bestätigung
read -p "Fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/6] System wird aktualisiert...${NC}"
apt update && apt upgrade -y

echo ""
echo -e "${YELLOW}[2/6] Pakete werden installiert...${NC}"
apt install -y \
    labwc \
    chromium \
    wlopm \
    wlr-randr \
    xdg-utils \
    fonts-dejavu \
    fonts-noto \
    unclutter

echo ""
echo -e "${YELLOW}[3/6] labwc Konfiguration wird erstellt...${NC}"

# labwc Konfigurationsverzeichnis erstellen
mkdir -p "$KIOSK_HOME/.config/labwc"

# rc.xml erstellen (mit hideCursor)
cat > "$KIOSK_HOME/.config/labwc/rc.xml" << 'EOF'
<?xml version="1.0"?>
<labwc_config>
  <core>
    <!-- Cursor ausblenden -->
    <hideCursor>true</hideCursor>
  </core>

  <keyboard>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="A-Tab">
      <action name="NextWindow"/>
    </keybind>
  </keyboard>

  <windowRules>
    <!-- Chromium im Vollbild ohne Dekoration -->
    <windowRule identifier="chromium*">
      <property name="skipTaskbar" value="yes"/>
      <action name="Maximize"/>
    </windowRule>
  </windowRules>
</labwc_config>
EOF

echo "  rc.xml erstellt (hideCursor aktiviert)"

# autostart erstellen
cat > "$KIOSK_HOME/.config/labwc/autostart" << EOF
#!/bin/bash

# Display-Standby deaktivieren (Display bleibt immer an)
wlopm --on '*' &
sleep 2

# Bildschirmschoner deaktivieren
export DISPLAY=:0

# Chromium im Kiosk-Modus starten
chromium \\
    --kiosk \\
    --noerrdialogs \\
    --disable-infobars \\
    --disable-session-crashed-bubble \\
    --disable-restore-session-state \\
    --disable-features=TranslateUI \\
    --disable-translate \\
    --no-first-run \\
    --start-fullscreen \\
    --start-maximized \\
    --autoplay-policy=no-user-gesture-required \\
    --check-for-update-interval=31536000 \\
    --disable-background-networking \\
    --disable-component-update \\
    --disable-default-apps \\
    --disable-extensions \\
    --disable-popup-blocking \\
    --password-store=basic \\
    "$KIOSK_URL" &
EOF

chmod +x "$KIOSK_HOME/.config/labwc/autostart"
echo "  autostart erstellt (Kiosk-Modus konfiguriert)"

# Berechtigungen setzen
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/labwc"

echo ""
echo -e "${YELLOW}[4/6] Chromium Managed Policy wird konfiguriert...${NC}"

# Chromium Policy Verzeichnis erstellen
mkdir -p /etc/chromium/policies/managed

# Translate deaktivieren
cat > /etc/chromium/policies/managed/disable_translate.json << 'EOF'
{
  "TranslateEnabled": false
}
EOF

echo "  Policy erstellt: TranslateEnabled = false"

echo ""
echo -e "${YELLOW}[5/6] Display-Einstellungen werden konfiguriert...${NC}"

# wlopm systemd Service für permanentes Display
cat > /etc/systemd/system/wlopm-keepalive.service << 'EOF'
[Unit]
Description=Keep display always on
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wlopm --on '*'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable wlopm-keepalive.service
echo "  wlopm Service aktiviert (Display bleibt immer an)"

echo ""
echo -e "${YELLOW}[6/6] Autostart für labwc wird konfiguriert...${NC}"

# .bash_profile für automatischen labwc Start
if ! grep -q "labwc" "$KIOSK_HOME/.bash_profile" 2>/dev/null; then
    cat >> "$KIOSK_HOME/.bash_profile" << 'EOF'

# Automatisch labwc starten auf TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec labwc
fi
EOF
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"
    echo "  Auto-Login konfiguriert"
fi

# Autologin für getty konfigurieren
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

systemctl daemon-reload
echo "  Automatisches Login für $KIOSK_USER konfiguriert"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Konfiguration:"
echo "  - Kiosk-URL: $KIOSK_URL"
echo "  - Benutzer:  $KIOSK_USER"
echo "  - labwc:     $KIOSK_HOME/.config/labwc/"
echo ""
echo -e "${YELLOW}URL nachträglich ändern:${NC}"
echo "  nano $KIOSK_HOME/.config/labwc/autostart"
echo ""
echo -e "${YELLOW}System jetzt neustarten:${NC}"
echo "  sudo reboot"
echo ""
