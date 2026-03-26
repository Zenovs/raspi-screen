# sicht!bar Screen – Raspberry Pi Kiosk-Setup

**Debian 13 (Trixie) / labwc (Wayland Compositor)**

Diese Dokumentation beschreibt, wie ein Raspberry Pi mit Debian 13 (Trixie) und labwc so konfiguriert wird, dass:

- Eine statische WLAN-IP verwendet wird
- Beim Booten automatisch Chromium im Kiosk-Modus mit einer bestimmten URL startet
- Bildschirmschoner / Standby / Console-Blanking deaktiviert sind
- Der Mauszeiger ausgeblendet wird, indem er einmal automatisch bewegt wird (Trigger für Webflow-Regel)
- Chromium keine Übersetzungsleiste für Englisch anbietet
- SSH weiterhin erreichbar bleibt

**Beispiel Ziel-URL:**
```
https://schnyder.webflow.io/screens/sichtbar-screen
```

---

## Startkette (Boot → Kiosk)

```
systemd → getty@tty1 (autologin) → bash → .bash_profile → exec labwc → autostart → chromium
```

1. systemd startet `getty@tty1` mit Autologin-Override
2. Benutzer wird automatisch auf tty1 eingeloggt (kein greetd/lightdm)
3. `.bash_profile` erkennt tty1 (`$(tty) = /dev/tty1`) und startet labwc via `exec`
4. labwc lädt `~/.config/labwc/environment` und führt `~/.config/labwc/autostart` aus
5. `autostart` startet wlopm (Display an), ydotool (Mausbewegung) und Chromium (Kiosk)

> **SSH bleibt unberührt:** `.bash_profile` prüft `$(tty)` – nur auf `/dev/tty1` wird labwc gestartet.

---

## 1. Statische IP für WLAN (Debian 13 / NetworkManager)

Debian 13 / Raspberry Pi OS (Trixie) nutzt den NetworkManager.

### Aktuelle Verbindungen anzeigen:

```bash
nmcli connection show
```

**Beispielausgabe:**
```
NAME                         UUID                                  TYPE      DEVICE
Schnyder Werbung Staff       e30476f0-d3a0-4fc5-b66e-7a2f3ced9876  wifi      wlan0
```

### Statische IP für diese Verbindung setzen:

> Gateway und IP an Umgebung anpassen!

```bash
sudo nmcli connection modify "Schnyder Werbung Staff" \
  ipv4.addresses 192.168.19.156/24 \
  ipv4.gateway 192.168.19.1 \
  ipv4.dns "1.1.1.1,8.8.8.8" \
  ipv4.method manual
```

### Verbindung neu starten:

> SSH-Verbindung bricht dabei ggf. ab!

```bash
sudo nmcli connection up "Schnyder Werbung Staff"
```

### Danach per SSH wieder verbinden:

```bash
ssh screen-sichtbar@192.168.19.156
```

Die IP bleibt nun auch nach Reboots erhalten.

---

## 2. Boot-Ziel und Autologin

### Display-Manager deaktivieren

RPi OS Trixie (Desktop) kommt mit `greetd` als Display-Manager. Dieser muss deaktiviert werden, um Konflikte mit dem getty-Autologin zu vermeiden:

```bash
sudo systemctl disable greetd.service 2>/dev/null || true
```

### graphical.target setzen:

```bash
sudo systemctl set-default graphical.target
```

### Getty-Autologin konfigurieren:

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin BENUTZERNAME --noclear %I \$TERM
EOF
sudo systemctl daemon-reload
```

> `BENUTZERNAME` durch den tatsächlichen Benutzernamen ersetzen (z.B. `screen-eingang`).

---

## 3. Chromium installieren (falls nicht vorhanden)

```bash
sudo apt update
sudo apt install chromium -y
```

**Browser-Binary:** `/usr/bin/chromium`

---

## 4. labwc Konfiguration

### .bash_profile – labwc automatisch starten

Die Datei `~/.bash_profile` startet labwc nur auf tty1:

```bash
# Standard .profile laden (PATH, etc.)
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

# Automatisch labwc starten auf TTY1 (nicht bei SSH-Sessions)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export XDG_SESSION_TYPE=wayland
    export MOZ_ENABLE_WAYLAND=1
    exec labwc > /tmp/labwc.log 2>&1
fi
```

### environment – Umgebungsvariablen

`~/.config/labwc/environment`:
```
WLR_LIBINPUT_NO_DEVICES=1
WLR_NO_HARDWARE_CURSORS=1
```

### rc.xml – Cursor verstecken

`~/.config/labwc/rc.xml`:
```xml
<?xml version="1.0"?>
<labwc_config>
  <core>
    <hideCursor>true</hideCursor>
  </core>

  <keyboard>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
  </keyboard>

  <windowRules>
    <windowRule identifier="chromium*">
      <property name="skipTaskbar" value="yes"/>
      <action name="Maximize"/>
    </windowRule>
  </windowRules>
</labwc_config>
```

### autostart – Kiosk-Startskript

`~/.config/labwc/autostart`:
```bash
#!/bin/bash

# Warten bis labwc Outputs initialisiert hat
sleep 2

# Display einschalten und Standby deaktivieren
wlopm --on '*' 2>/dev/null || true

# Display-Keepalive (alle 5 Minuten)
(while true; do sleep 300; wlopm --on '*' 2>/dev/null || true; done) &

# ydotool Daemon starten
(sleep 2 && ydotoold) &

# Maus bewegen nach 50s (triggert Webflow Cursor-Hider)
(sleep 50 && ydotool mousemove 100 100) &

# Chromium im Kiosk-Modus
chromium \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --kiosk \
    --incognito \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --no-first-run \
    --password-store=basic \
    --disable-translate \
    --disable-features=Translate,TranslateUI,LanguageDetection,TranslateSettings,MediaRouter \
    --start-fullscreen \
    --start-maximized \
    --autoplay-policy=no-user-gesture-required \
    --check-for-update-interval=31536000 \
    --disable-background-networking \
    --disable-component-update \
    --disable-default-apps \
    --disable-extensions \
    --disable-popup-blocking \
    --disable-gpu-sandbox \
    --disable-crash-reporter \
    --disable-breakpad \
    --disable-hang-monitor \
    --disable-domain-reliability \
    --disable-client-side-phishing-detection \
    --renderer-process-limit=1 \
    "https://schnyder.webflow.io/screens/sichtbar-screen" &
```

### Hinweise:

- `--ozone-platform=wayland` und `--enable-features=UseOzonePlatform` sind **zwingend erforderlich** für Wayland
- `--incognito` stellt sicher, dass keine persistenten Daten/Popups zwischen Starts überleben
- `--renderer-process-limit=1` spart RAM auf dem RPi 3 (1 GB)
- `--disable-crash-reporter` und `--disable-breakpad` verhindern Crash-Dialoge
- Die `Translate*`-Flags und die Chromium-Policy reduzieren Übersetzungsdialoge

---

## 5. Mausbewegung automatisieren mit ydotool (Wayland-kompatibel)

Unter Wayland funktioniert `xdotool` nicht. Stattdessen wird `ydotool` verwendet.

### 5.1. Abhängigkeiten installieren

```bash
sudo apt install cmake libevdev-dev git scdoc -y
```

### 5.2. ydotool aus den Quellen bauen und installieren

```bash
cd /tmp
git clone https://github.com/ReimuNotMoe/ydotool.git ydotool-build
cd ydotool-build
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
cd /
rm -rf /tmp/ydotool-build
```

Damit werden `ydotool` und `ydotoold` unter `/usr/local/bin/` installiert.

### 5.3. Zugriffsrechte für /dev/uinput (Eingabeemulation)

```bash
sudo usermod -aG input $USER
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/80-uinput.rules

# uinput Modul beim Boot laden
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf
```

**Anschliessend ist ein Neustart erforderlich, damit die Gruppenänderung aktiv wird.**

---

## 6. Console Blanking deaktivieren

Zusätzlich zur Wayland-Konfiguration muss das Kernel-Console-Blanking deaktiviert werden:

```bash
# consoleblank=0 an cmdline.txt anhängen (RPi OS Trixie)
sudo sed -i 's/$/ consoleblank=0/' /boot/firmware/cmdline.txt
```

---

## 7. Verhalten nach dem Boot

### Ablauf nach einem Neustart:

1. System bootet in `graphical.target`
2. `getty@tty1` loggt den Benutzer automatisch ein (Autologin-Override)
3. `.bash_profile` erkennt tty1 und startet `labwc` via `exec`
4. labwc lädt `environment` und führt `autostart` aus:
   - `wlopm --on '*'` schaltet das Display ein
   - Keepalive-Loop hält das Display alle 5 Minuten aktiv
   - `ydotoold` startet im Hintergrund
   - Chromium startet im Kiosk-/Inkognito-Modus mit Wayland-Flags
5. Nach 50 Sekunden wird eine Mausbewegung simuliert (ydotool)
6. Die Webflow-Logik blendet den Cursor nach Inaktivität aus
7. **Nutzer sehen nur die Webflow-Seite im Vollbild, ohne Taskleiste, ohne Adressleiste, ohne Mauszeiger**

---

## 8. Bekannte Einschränkungen und Hinweise

### Übersetzungsleiste

Trotz der Flags kann Chromium bei Seiten, die als `lang="en"` deklariert sind, gelegentlich einen Übersetzungsbalken zeigen.

**Empfohlene Ergänzung auf Webflow-Seite:**
- Das HTML-lang-Attribut auf `de` oder `de-CH` setzen

### RPi 3 mit 1 GB RAM

- Chromium nutzt `--renderer-process-limit=1` um RAM zu sparen
- Bei komplexen Webseiten kann es zu Verlangsamungen kommen
- Bei Bedarf: `WLR_RENDERER=pixman` in der environment-Datei setzen (Software-Rendering)

### ydotool Wartung

Falls `ydotool` in einer späteren Debian-Version paketiert wird, kann das manuelle Build ersetzt werden.

### greetd-Konflikt

RPi OS Trixie (Desktop-Variante) verwendet `greetd` als Display-Manager. Das Install-Skript deaktiviert greetd automatisch, da es mit dem getty-Autologin kollidiert.

---

## 9. Verwendung des Install-Skripts

Das Repository enthält ein automatisches Install-Skript, das alle oben beschriebenen Schritte durchführt:

```bash
# Standard-Installation
sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen

# Mit statischer IP-Konfiguration
sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen \
  --static-ip "Schnyder Werbung Staff" 192.168.19.156/24 192.168.19.1
```

### Das Skript führt folgende Schritte aus:

1. Installiert alle benötigten Pakete
2. Baut ydotool aus den Quellen
3. Konfiguriert uinput-Zugriffsrechte und Modul-Laden
4. Erstellt labwc Konfiguration (rc.xml, environment, autostart)
5. Konfiguriert Chromium Policies
6. Deaktiviert greetd (falls vorhanden)
7. Richtet getty-Autologin und .bash_profile ein
8. Deaktiviert Console Blanking
9. (Optional) Konfiguriert statische IP

---

## 10. Webflow-spezifische Hinweise

### Cursor-Hider-Logik

Die sicht!bar Screens nutzen eine Webflow-spezifische CSS/JS-Regel, die den Mauszeiger nach einer Bewegung automatisch ausblendet. Damit diese Regel greift:

1. Eine Mausbewegung muss erkannt werden (daher ydotool)
2. Nach kurzer Inaktivität wird der Cursor via CSS ausgeblendet

### Empfehlungen für die Webflow-Seite:

- `lang="de"` oder `lang="de-CH"` im HTML-Tag setzen
- Keine `lang="en"`-Deklaration verwenden
- Cursor-Hider-Regel implementieren

---

*Diese Dokumentation wurde für das schnelle Deployment von sicht!bar Raspberry Pi Kiosk-Systemen erstellt.*
