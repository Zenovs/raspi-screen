#!/bin/bash
#
# Raspberry Pi Kiosk Installer
# Für Debian 13 mit labwc (Wayland Compositor)
#
# Verwendung: sudo ./install.sh [KIOSK_URL] [--static-ip "NETWORK_NAME" IP/MASK GATEWAY]
# Beispiel:   sudo ./install.sh https://example.com/dashboard
# Beispiel mit statischer IP:
#   sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen \
#     --static-ip "Schnyder Werbung Staff" 192.168.19.156/24 192.168.19.1
#

set -e

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Standard-URL (Platzhalter)
DEFAULT_URL="https://deine-url.ch"
KIOSK_URL=""
STATIC_IP_NETWORK=""
STATIC_IP_ADDRESS=""
STATIC_IP_GATEWAY=""

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        --static-ip)
            STATIC_IP_NETWORK="$2"
            STATIC_IP_ADDRESS="$3"
            STATIC_IP_GATEWAY="$4"
            shift 4
            ;;
        -*)
            echo -e "${RED}Unbekannte Option: $1${NC}"
            exit 1
            ;;
        *)
            if [ -z "$KIOSK_URL" ]; then
                KIOSK_URL="$1"
            fi
            shift
            ;;
    esac
done

# Standard-URL setzen falls nicht angegeben
KIOSK_URL="${KIOSK_URL:-$DEFAULT_URL}"

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
    echo "Verwendung: sudo $0 [KIOSK_URL] [--static-ip \"NETWORK\" IP/MASK GATEWAY]"
    exit 1
fi

echo -e "${YELLOW}Konfiguration:${NC}"
echo "  Kiosk-URL:    $KIOSK_URL"
echo "  Benutzer:     $KIOSK_USER"
echo "  Home-Pfad:    $KIOSK_HOME"
if [ -n "$STATIC_IP_NETWORK" ]; then
    echo "  Netzwerk:     $STATIC_IP_NETWORK"
    echo "  Statische IP: $STATIC_IP_ADDRESS"
    echo "  Gateway:      $STATIC_IP_GATEWAY"
fi
echo ""

# Bestätigung
read -p "Fortfahren? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/8] System wird aktualisiert...${NC}"
apt update && apt upgrade -y

echo ""
echo -e "${YELLOW}[2/8] Pakete werden installiert...${NC}"
apt install -y \
    labwc \
    chromium \
    wlopm \
    wlr-randr \
    xdg-utils \
    fonts-dejavu \
    fonts-noto \
    cmake \
    libevdev-dev \
    git \
    scdoc

echo ""
echo -e "${YELLOW}[3/8] ydotool wird aus Quellen gebaut...${NC}"

# ydotool Installation
YDOTOOL_DIR="/tmp/ydotool-build"
if [ ! -f /usr/local/bin/ydotool ]; then
    rm -rf "$YDOTOOL_DIR"
    git clone https://github.com/ReimuNotMoe/ydotool.git "$YDOTOOL_DIR"
    cd "$YDOTOOL_DIR"
    mkdir -p build
    cd build
    cmake ..
    make
    make install
    cd /
    rm -rf "$YDOTOOL_DIR"
    echo "  ydotool und ydotoold installiert in /usr/local/bin/"
else
    echo "  ydotool ist bereits installiert, überspringe..."
fi

# uinput Zugriffsrechte konfigurieren
echo ""
echo -e "${YELLOW}[4/8] uinput Zugriffsrechte werden konfiguriert...${NC}"
usermod -aG input "$KIOSK_USER"
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' > /etc/udev/rules.d/80-uinput.rules
echo "  Benutzer $KIOSK_USER zur Gruppe 'input' hinzugefügt"
echo "  udev-Regel für /dev/uinput erstellt"

echo ""
echo -e "${YELLOW}[5/8] labwc Konfiguration wird erstellt...${NC}"

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

# environment erstellen (labwc lädt diese Datei beim Start)
cat > "$KIOSK_HOME/.config/labwc/environment" << 'EOF'
# Sicherstellen, dass labwc auch ohne angeschlossene Eingabegeräte startet
WLR_LIBINPUT_NO_DEVICES=1
# GPU-Rendering (Pixman als Fallback für ältere RPi-Modelle)
# WLR_RENDERER=pixman
EOF

echo "  environment erstellt (WLR_LIBINPUT_NO_DEVICES gesetzt)"

# autostart erstellen
cat > "$KIOSK_HOME/.config/labwc/autostart" << EOF
#!/bin/bash

# Kurz warten, bis labwc Outputs vollständig initialisiert hat
sleep 2

# Bildschirmschoner und Standby deaktivieren
# wlopm --on schaltet alle Ausgänge ein und verhindert Standby
wlopm --on '*' 2>/dev/null || true

# ydotool Daemon starten, um später die Maus zu bewegen
# Warten, bis /dev/uinput verfügbar ist
(sleep 2 && ydotoold) &

# 50 Sekunden warten, bis System und Chromium komplett geladen sind,
# dann Maus um 100 Pixel bewegen, damit die Webflow-Regel den Cursor versteckt
(sleep 50 && ydotool mousemove 100 100) &

# Chromium im Kiosk- und Inkognito-Modus starten
# --ozone-platform=wayland ist ERFORDERLICH für Wayland-Rendering
chromium \\
    --ozone-platform=wayland \\
    --enable-features=UseOzonePlatform \\
    --kiosk \\
    --incognito \\
    --noerrdialogs \\
    --disable-infobars \\
    --disable-session-crashed-bubble \\
    --disable-restore-session-state \\
    --no-first-run \\
    --password-store=basic \\
    --disable-translate \\
    --disable-features=Translate,TranslateUI,LanguageDetection,TranslateSettings \\
    --start-fullscreen \\
    --start-maximized \\
    --autoplay-policy=no-user-gesture-required \\
    --check-for-update-interval=31536000 \\
    --disable-background-networking \\
    --disable-component-update \\
    --disable-default-apps \\
    --disable-extensions \\
    --disable-popup-blocking \\
    --disable-gpu-sandbox \\
    "$KIOSK_URL" &
EOF

chmod +x "$KIOSK_HOME/.config/labwc/autostart"
echo "  autostart erstellt (Wayland-Flags, ydotool, Kiosk-Modus konfiguriert)"

# Berechtigungen setzen
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/labwc"

echo ""
echo -e "${YELLOW}[6/8] Chromium Managed Policy und Boot-Target werden konfiguriert...${NC}"

# Chromium Policy Verzeichnis erstellen
mkdir -p /etc/chromium/policies/managed

# Translate deaktivieren
cat > /etc/chromium/policies/managed/disable_translate.json << 'EOF'
{
  "TranslateEnabled": false
}
EOF

echo "  Policy erstellt: TranslateEnabled = false"

# graphical.target setzen
current_target=$(systemctl get-default)
if [ "$current_target" != "graphical.target" ]; then
    systemctl set-default graphical.target
    echo "  Boot-Target auf graphical.target gesetzt (war: $current_target)"
else
    echo "  Boot-Target ist bereits graphical.target"
fi

echo ""
echo -e "${YELLOW}[7/8] Display-Einstellungen und Autologin werden konfiguriert...${NC}"

# wlopm-keepalive als systemd USER-Service (nicht System-Service!)
# System-Services haben keinen Zugang zur Wayland-Session.
# Stattdessen verwenden wir nur die autostart-Methode (wlopm im labwc autostart).
# Falls ein alter System-Service existiert, deaktivieren wir ihn.
if systemctl is-enabled wlopm-keepalive.service 2>/dev/null; then
    systemctl disable wlopm-keepalive.service 2>/dev/null || true
    echo "  Alter wlopm System-Service deaktiviert (inkompatibel mit Wayland-Session)"
fi
rm -f /etc/systemd/system/wlopm-keepalive.service

# Stattdessen: wlopm-keepalive als systemd User-Service einrichten
KIOSK_USER_ID=$(id -u "$KIOSK_USER")
mkdir -p "$KIOSK_HOME/.config/systemd/user"
cat > "$KIOSK_HOME/.config/systemd/user/wlopm-keepalive.service" << 'EOF'
[Unit]
Description=Keep display always on (Wayland)
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wlopm --on *
RemainAfterExit=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/systemd"
# Aktivieren des User-Service (wird bei nächster Wayland-Session gestartet)
su - "$KIOSK_USER" -c "systemctl --user daemon-reload 2>/dev/null || true"
su - "$KIOSK_USER" -c "systemctl --user enable wlopm-keepalive.service 2>/dev/null || true"
echo "  wlopm als User-Service konfiguriert (Display bleibt immer an)"

# .bash_profile für automatischen labwc Start
# WICHTIG: Zuerst .profile sourcen, damit PATH und andere Variablen gesetzt sind
if ! grep -q "labwc" "$KIOSK_HOME/.bash_profile" 2>/dev/null; then
    cat >> "$KIOSK_HOME/.bash_profile" << 'BASHEOF'

# Standard .profile laden (PATH, etc.)
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

# Automatisch labwc starten auf TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export XDG_SESSION_TYPE=wayland
    export MOZ_ENABLE_WAYLAND=1
    # labwc starten – dies setzt WAYLAND_DISPLAY und XDG_RUNTIME_DIR automatisch
    exec labwc > /tmp/labwc.log 2>&1
fi
BASHEOF
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"
    echo "  Auto-Login konfiguriert (.bash_profile mit .profile-Source)"
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

# Optionale statische IP-Konfiguration
echo ""
echo -e "${YELLOW}[8/8] Optionale Konfigurationen...${NC}"

if [ -n "$STATIC_IP_NETWORK" ] && [ -n "$STATIC_IP_ADDRESS" ] && [ -n "$STATIC_IP_GATEWAY" ]; then
    echo "  Statische IP wird konfiguriert..."
    nmcli connection modify "$STATIC_IP_NETWORK" \
        ipv4.addresses "$STATIC_IP_ADDRESS" \
        ipv4.gateway "$STATIC_IP_GATEWAY" \
        ipv4.dns "1.1.1.1,8.8.8.8" \
        ipv4.method manual
    echo "  Statische IP konfiguriert für '$STATIC_IP_NETWORK'"
    echo "  IP: $STATIC_IP_ADDRESS, Gateway: $STATIC_IP_GATEWAY"
    echo -e "  ${YELLOW}Hinweis: Die Netzwerkverbindung muss nach dem Neustart neu aufgebaut werden.${NC}"
else
    echo "  Keine statische IP-Konfiguration angefordert (übersprungen)"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Konfiguration:"
echo "  - Kiosk-URL: $KIOSK_URL"
echo "  - Benutzer:  $KIOSK_USER"
echo "  - labwc:     $KIOSK_HOME/.config/labwc/"
echo "  - ydotool:   /usr/local/bin/ydotool"
echo ""
echo -e "${YELLOW}URL nachträglich ändern:${NC}"
echo "  nano $KIOSK_HOME/.config/labwc/autostart"
echo ""
echo -e "${RED}⚠️  WICHTIG: Ein Neustart ist erforderlich!${NC}"
echo -e "${RED}   Die uinput-Gruppenrechte werden erst nach dem Neustart aktiv.${NC}"
echo ""
echo -e "${YELLOW}System jetzt neustarten:${NC}"
echo "  sudo reboot"
echo ""
