#!/bin/bash
#
# Raspberry Pi Kiosk Installer
# Für Debian 13 (Trixie) mit labwc (Wayland Compositor)
#
# Verwendung: sudo ./install.sh [KIOSK_URL] [--static-ip "NETWORK_NAME" IP/MASK GATEWAY]
# Beispiel:   sudo ./install.sh https://example.com/dashboard
# Beispiel mit statischer IP:
#   sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen \
#     --static-ip "Schnyder Werbung Staff" 192.168.19.156/24 192.168.19.1
#

set -euo pipefail

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
            if [[ $# -lt 4 ]]; then
                echo -e "${RED}Fehler: --static-ip benötigt 3 Argumente: NETWORK IP/MASK GATEWAY${NC}"
                echo "Beispiel: --static-ip \"Mein WLAN\" 192.168.1.100/24 192.168.1.1"
                exit 1
            fi
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

# Prüfen ob der Benutzer existiert
if ! id "$KIOSK_USER" &>/dev/null; then
    echo -e "${RED}Fehler: Benutzer '$KIOSK_USER' existiert nicht!${NC}"
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

# Bestätigung (überspringe bei nicht-interaktivem Terminal)
if [ -t 0 ]; then
    read -p "Fortfahren? (j/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
        echo "Installation abgebrochen."
        exit 0
    fi
else
    echo -e "${YELLOW}Nicht-interaktiver Modus erkannt – Installation wird fortgesetzt...${NC}"
fi

echo ""
echo -e "${YELLOW}[1/9] System wird aktualisiert...${NC}"
apt-get update && apt-get upgrade -y

echo ""
echo -e "${YELLOW}[2/9] Pakete werden installiert...${NC}"
apt-get install -y \
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
echo -e "${YELLOW}[3/9] ydotool wird aus Quellen gebaut...${NC}"

# ydotool Installation (in Subshell für sauberes Verzeichnis-Management)
if [ ! -f /usr/local/bin/ydotool ]; then
    (
        YDOTOOL_DIR="/tmp/ydotool-build"
        rm -rf "$YDOTOOL_DIR"
        git clone https://github.com/ReimuNotMoe/ydotool.git "$YDOTOOL_DIR"
        cd "$YDOTOOL_DIR"
        mkdir -p build
        cd build
        cmake ..
        make -j"$(nproc)"
        make install
    )
    rm -rf /tmp/ydotool-build
    echo "  ydotool und ydotoold installiert in /usr/local/bin/"
else
    echo "  ydotool ist bereits installiert, überspringe..."
fi

# uinput Zugriffsrechte konfigurieren
echo ""
echo -e "${YELLOW}[4/9] uinput Zugriffsrechte werden konfiguriert...${NC}"
usermod -aG input "$KIOSK_USER"
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' > /etc/udev/rules.d/80-uinput.rules

# uinput Modul beim Boot laden
if ! grep -q '^uinput$' /etc/modules-load.d/*.conf 2>/dev/null; then
    echo "uinput" > /etc/modules-load.d/uinput.conf
    echo "  uinput Modul wird beim Boot geladen"
fi

echo "  Benutzer $KIOSK_USER zur Gruppe 'input' hinzugefügt"
echo "  udev-Regel für /dev/uinput erstellt"

echo ""
echo -e "${YELLOW}[5/9] labwc Konfiguration wird erstellt...${NC}"

# labwc Konfigurationsverzeichnis erstellen
mkdir -p "$KIOSK_HOME/.config/labwc"

# rc.xml erstellen (mit hideCursor und Idle-Konfiguration)
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
# Hardware-Cursor deaktivieren (vermeidet Rendering-Probleme auf RPi)
WLR_NO_HARDWARE_CURSORS=1
# GPU-Rendering (Pixman als Fallback für ältere RPi-Modelle)
# WLR_RENDERER=pixman
EOF

echo "  environment erstellt (WLR_LIBINPUT_NO_DEVICES, WLR_NO_HARDWARE_CURSORS gesetzt)"

# autostart erstellen
cat > "$KIOSK_HOME/.config/labwc/autostart" << EOF
#!/bin/bash

# Kurz warten, bis labwc Outputs vollständig initialisiert hat
sleep 2

# Bildschirmschoner und Standby deaktivieren
# wlopm --on schaltet alle Ausgänge ein und verhindert Standby
wlopm --on '*' 2>/dev/null || true

# Display-Keepalive: alle 5 Minuten sicherstellen, dass der Bildschirm an bleibt
(while true; do sleep 300; wlopm --on '*' 2>/dev/null || true; done) &

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
    --disable-features=Translate,TranslateUI,LanguageDetection,TranslateSettings,MediaRouter \\
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
    --disable-crash-reporter \\
    --disable-breakpad \\
    --disable-hang-monitor \\
    --disable-domain-reliability \\
    --disable-client-side-phishing-detection \\
    --renderer-process-limit=1 \\
    "$KIOSK_URL" &
EOF

chmod +x "$KIOSK_HOME/.config/labwc/autostart"
echo "  autostart erstellt (Wayland-Flags, ydotool, Kiosk-Modus konfiguriert)"

# Berechtigungen setzen
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/labwc"

echo ""
echo -e "${YELLOW}[6/9] Chromium Managed Policy und Boot-Target werden konfiguriert...${NC}"

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
echo -e "${YELLOW}[7/9] Autologin und Display-Manager werden konfiguriert...${NC}"

# greetd deaktivieren falls vorhanden (RPi OS Desktop kommt mit greetd,
# das auf tty1 einen eigenen Login-Manager startet und mit getty autologin kollidiert)
if command -v greetd &>/dev/null || systemctl is-enabled greetd.service &>/dev/null 2>&1; then
    systemctl disable greetd.service 2>/dev/null || true
    systemctl stop greetd.service 2>/dev/null || true
    echo "  greetd deaktiviert (kollidiert mit getty-autologin)"
fi

# Andere Display-Manager deaktivieren (lightdm, gdm3, sddm)
for dm in lightdm gdm3 sddm; do
    if systemctl is-enabled "${dm}.service" &>/dev/null 2>&1; then
        systemctl disable "${dm}.service" 2>/dev/null || true
        echo "  ${dm} deaktiviert"
    fi
done

# Falls ein alter wlopm System-Service existiert, deaktivieren
if systemctl is-enabled wlopm-keepalive.service 2>/dev/null; then
    systemctl disable wlopm-keepalive.service 2>/dev/null || true
    echo "  Alter wlopm System-Service deaktiviert"
fi
rm -f /etc/systemd/system/wlopm-keepalive.service

# wlopm-keepalive als systemd User-Service einrichten
mkdir -p "$KIOSK_HOME/.config/systemd/user"
cat > "$KIOSK_HOME/.config/systemd/user/wlopm-keepalive.service" << 'EOF'
[Unit]
Description=Keep display always on (Wayland)
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/usr/bin/wlopm --on '*' 2>/dev/null || true"
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF

chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/systemd"

# User-Service manuell aktivieren (symlink), da systemctl --user von root nicht funktioniert
mkdir -p "$KIOSK_HOME/.config/systemd/user/graphical-session.target.wants"
ln -sf ../wlopm-keepalive.service "$KIOSK_HOME/.config/systemd/user/graphical-session.target.wants/wlopm-keepalive.service"
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/systemd"

# Linger aktivieren damit User-Services auch ohne aktive Login-Session laufen
loginctl enable-linger "$KIOSK_USER" 2>/dev/null || true

echo "  wlopm als User-Service konfiguriert (Display bleibt immer an)"

# .bash_profile für automatischen labwc Start
# WICHTIG: Zuerst .profile sourcen, damit PATH und andere Variablen gesetzt sind
if ! grep -q "labwc" "$KIOSK_HOME/.bash_profile" 2>/dev/null; then
    cat >> "$KIOSK_HOME/.bash_profile" << 'BASHEOF'

# Standard .profile laden (PATH, etc.)
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

# Automatisch labwc starten auf TTY1 (nicht bei SSH-Sessions)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export XDG_SESSION_TYPE=wayland
    export MOZ_ENABLE_WAYLAND=1
    # labwc starten – dies setzt WAYLAND_DISPLAY und XDG_RUNTIME_DIR automatisch
    exec labwc > /tmp/labwc.log 2>&1
fi
BASHEOF
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"
    echo "  .bash_profile erstellt (labwc-Start auf tty1, SSH bleibt unberührt)"
fi

# Autologin für getty konfigurieren
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

systemctl daemon-reload
echo "  Automatisches Login für $KIOSK_USER auf tty1 konfiguriert"

echo ""
echo -e "${YELLOW}[8/9] Display-Einstellungen (Console Blanking, DPMS)...${NC}"

# Console Blanking deaktivieren (Kernel-Parameter)
# RPi OS Trixie: /boot/firmware/cmdline.txt
# Ältere RPi OS: /boot/cmdline.txt
CMDLINE_FILE=""
if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
    if ! grep -q "consoleblank=0" "$CMDLINE_FILE"; then
        # cmdline.txt ist eine einzelne Zeile – Parameter anhängen
        sed -i 's/$/ consoleblank=0/' "$CMDLINE_FILE"
        echo "  Console Blanking deaktiviert (consoleblank=0 in $CMDLINE_FILE)"
    else
        echo "  Console Blanking ist bereits deaktiviert"
    fi
else
    echo -e "  ${YELLOW}Warnung: cmdline.txt nicht gefunden – Console Blanking manuell deaktivieren${NC}"
fi

# Optionale statische IP-Konfiguration
echo ""
echo -e "${YELLOW}[9/9] Optionale Konfigurationen...${NC}"

if [ -n "$STATIC_IP_NETWORK" ] && [ -n "$STATIC_IP_ADDRESS" ] && [ -n "$STATIC_IP_GATEWAY" ]; then
    echo "  Statische IP wird konfiguriert..."

    # Prüfen ob die Verbindung existiert
    if nmcli connection show "$STATIC_IP_NETWORK" &>/dev/null; then
        nmcli connection modify "$STATIC_IP_NETWORK" \
            ipv4.addresses "$STATIC_IP_ADDRESS" \
            ipv4.gateway "$STATIC_IP_GATEWAY" \
            ipv4.dns "1.1.1.1,8.8.8.8" \
            ipv4.method manual

        # Verbindung vor Manipulation durch NM schützen (autoconnect-priority erhöhen)
        nmcli connection modify "$STATIC_IP_NETWORK" \
            connection.autoconnect yes \
            connection.autoconnect-priority 100 2>/dev/null || true

        echo "  Statische IP konfiguriert für '$STATIC_IP_NETWORK'"
        echo "  IP: $STATIC_IP_ADDRESS, Gateway: $STATIC_IP_GATEWAY, DNS: 1.1.1.1, 8.8.8.8"
        echo -e "  ${YELLOW}Hinweis: Die Netzwerkverbindung wird nach dem Neustart neu aufgebaut.${NC}"
    else
        echo -e "  ${RED}Fehler: Netzwerk '$STATIC_IP_NETWORK' nicht gefunden!${NC}"
        echo "  Verfügbare Verbindungen:"
        nmcli connection show | head -10
        echo -e "  ${YELLOW}Statische IP übersprungen – bitte manuell konfigurieren.${NC}"
    fi
else
    echo "  Keine statische IP-Konfiguration angefordert (übersprungen)"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Konfiguration:"
echo "  - Kiosk-URL:      $KIOSK_URL"
echo "  - Benutzer:       $KIOSK_USER"
echo "  - labwc-Konfig:   $KIOSK_HOME/.config/labwc/"
echo "  - ydotool:        /usr/local/bin/ydotool"
echo "  - Console Blank:  deaktiviert"
echo "  - Display-Manager: greetd deaktiviert, getty-autologin aktiv"
echo ""
echo -e "${YELLOW}Startkette nach Reboot:${NC}"
echo "  systemd → getty (autologin) → bash_profile → labwc → autostart → chromium"
echo ""
echo -e "${YELLOW}URL nachträglich ändern:${NC}"
echo "  nano $KIOSK_HOME/.config/labwc/autostart"
echo ""
echo -e "${RED}⚠️  WICHTIG: Ein Neustart ist erforderlich!${NC}"
echo -e "${RED}   Die uinput-Gruppenrechte und Console-Blanking-Einstellung${NC}"
echo -e "${RED}   werden erst nach dem Neustart aktiv.${NC}"
echo ""
echo -e "${YELLOW}System jetzt neustarten:${NC}"
echo "  sudo reboot"
echo ""
