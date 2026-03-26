# Raspberry Pi Kiosk Setup

Automatisches Setup-Skript für einen Raspberry Pi Kiosk mit **Debian 13 (Trixie)** und **labwc** (Wayland Compositor).

## 🎯 Funktionen

- **Chromium im Kiosk-Modus** – Vollbild ohne Adressleiste, Inkognito-Modus
- **Versteckter Cursor** – Kein Mauszeiger sichtbar (via labwc hideCursor + ydotool + Webflow-Logik)
- **Display immer an** – Kein Standby/Bildschirmschoner/Console-Blanking
- **Auto-Login** – Startet automatisch beim Hochfahren (getty-autologin → labwc)
- **Übersetzung deaktiviert** – Keine Chrome-Übersetzungsdialoge
- **Automatische Mausbewegung** – Triggert Cursor-Hider via ydotool
- **Optionale statische IP** – Netzwerkkonfiguration via nmcli
- **SSH bleibt erreichbar** – labwc startet nur auf tty1, nicht bei SSH

## 📋 Systemanforderungen

- Raspberry Pi (3, 4 oder 5)
- **Debian 13 (Trixie)** / Raspberry Pi OS mit labwc
- Internetverbindung
- SSH-Zugang (empfohlen)

## 🚀 Schnellinstallation (One-Liner)

### Mit curl:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Zenovs/raspi-screen/main/install.sh)" -- https://deine-url.ch/dashboard
```

### Mit wget:
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/Zenovs/raspi-screen/main/install.sh)" -- https://deine-url.ch/dashboard
```

### Beispiel mit sicht!bar Screen:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Zenovs/raspi-screen/main/install.sh)" -- https://schnyder.webflow.io/screens/sichtbar-screen
```

## 📖 Schritt-für-Schritt Anleitung

### 1. Raspberry Pi vorbereiten

```bash
# System aktualisieren
sudo apt update && sudo apt upgrade -y

# Git installieren (falls nicht vorhanden)
sudo apt install -y git
```

### 2. Repository klonen

```bash
git clone https://github.com/Zenovs/raspi-screen.git
cd raspi-screen
```

### 3. Installationsskript ausführen

```bash
# Mit eigener URL
sudo ./install.sh https://example.com/meine-seite

# Oder mit der sicht!bar URL
sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen

# Mit statischer IP-Konfiguration
sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen \
  --static-ip "Schnyder Werbung Staff" 192.168.19.156/24 192.168.19.1
```

### 4. System neustarten

```bash
sudo reboot
```

> ⚠️ **Wichtig:** Ein Neustart ist erforderlich, damit die uinput-Gruppenrechte und Console-Blanking-Einstellung aktiv werden!

## 🔄 Startkette nach Reboot

```
systemd → getty (autologin auf tty1) → bash → .bash_profile → exec labwc → autostart → chromium
```

1. systemd startet `getty@tty1` mit Autologin-Override
2. Benutzer wird automatisch auf tty1 eingeloggt
3. `.bash_profile` erkennt tty1 und startet `labwc`
4. labwc lädt `~/.config/labwc/environment` und führt `autostart` aus
5. `autostart` startet wlopm, ydotool und Chromium im Kiosk-Modus

> **Hinweis:** SSH-Sessions sind davon nicht betroffen – labwc startet nur auf tty1.

## ⚙️ Statische IP-Konfiguration (Optional)

Das Skript unterstützt die optionale Konfiguration einer statischen IP über NetworkManager:

```bash
sudo ./install.sh https://example.com/dashboard \
  --static-ip "NETZWERK_NAME" IP_ADRESSE/MASKE GATEWAY
```

**Beispiel:**
```bash
sudo ./install.sh https://schnyder.webflow.io/screens/sichtbar-screen \
  --static-ip "Schnyder Werbung Staff" 192.168.19.156/24 192.168.19.1
```

**Parameter:**
- `NETZWERK_NAME`: Name der WLAN-Verbindung (aus `nmcli connection show`)
- `IP_ADRESSE/MASKE`: Gewünschte IP mit Subnetzmaske (z.B. `192.168.19.156/24`)
- `GATEWAY`: Gateway-Adresse (z.B. `192.168.19.1`)

## 🖱️ ydotool und automatische Mausbewegung

Unter Wayland funktioniert `xdotool` nicht. Das Skript installiert stattdessen **ydotool** aus den Quellen.

### Was macht ydotool?

- `ydotoold` läuft als Daemon im Hintergrund
- Nach 50 Sekunden wird die Maus automatisch um 100 Pixel bewegt
- Diese Bewegung triggert die Webflow-Regel zum Ausblenden des Cursors

### Warum 50 Sekunden?

Dies gibt Chromium und der Webseite genügend Zeit zum vollständigen Laden, bevor die Mausbewegung den Cursor-Hider aktiviert.

## 🌐 Webflow-spezifische Hinweise

### Cursor-Hider-Logik

Die sicht!bar Screens nutzen eine Webflow-spezifische CSS/JS-Regel:

1. Eine Mausbewegung wird erkannt (via ydotool nach 50s)
2. Nach kurzer Inaktivität wird der Cursor via CSS ausgeblendet
3. Der Nutzer sieht nur die Webflow-Seite im Vollbild

### Empfehlungen für Webflow:

- `lang="de"` oder `lang="de-CH"` im HTML-Tag setzen (verhindert Übersetzungsdialoge)
- Cursor-Hider-Regel implementieren

## ⚙️ URL nachträglich ändern

Die Kiosk-URL befindet sich in der autostart-Datei:

```bash
nano ~/.config/labwc/autostart
```

Ändere die URL am Ende der Chromium-Zeile und starte neu:

```bash
sudo reboot
```

## 📁 Installierte Konfigurationsdateien

| Datei | Beschreibung |
|-------|-------------|
| `~/.config/labwc/rc.xml` | labwc Konfiguration (hideCursor) |
| `~/.config/labwc/autostart` | Chromium Kiosk Startskript mit ydotool |
| `~/.config/labwc/environment` | labwc Umgebungsvariablen |
| `~/.config/systemd/user/wlopm-keepalive.service` | Display-Standby deaktiviert (User-Service) |
| `~/.bash_profile` | Auto-Start von labwc auf tty1 |
| `/etc/chromium/policies/managed/disable_translate.json` | Chromium Policy |
| `/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Getty Autologin |
| `/etc/udev/rules.d/80-uinput.rules` | uinput-Zugriffsrechte für ydotool |
| `/etc/modules-load.d/uinput.conf` | uinput Modul beim Boot laden |
| `/usr/local/bin/ydotool` | ydotool Binary |
| `/usr/local/bin/ydotoold` | ydotool Daemon |

## 📦 Installierte Pakete

- `labwc` – Wayland Compositor
- `chromium` – Web Browser
- `wlopm` – Wayland Output Power Management
- `wlr-randr` – Display-Konfiguration
- `cmake`, `libevdev-dev`, `git`, `scdoc` – Build-Dependencies für ydotool
- `fonts-dejavu`, `fonts-noto` – Schriftarten

## 🔧 Troubleshooting

### Schwarzer Bildschirm nach Neustart

```bash
# Per SSH verbinden und labwc-Log prüfen
cat /tmp/labwc.log

# labwc manuell starten (auf tty1 per SSH-Befehl)
# Erst prüfen ob labwc läuft:
ps aux | grep labwc

# Journal prüfen
journalctl -xe --no-pager | tail -50
```

### Cursor wird trotzdem angezeigt

1. Prüfe ob ydotool läuft:
```bash
ps aux | grep ydotool
```

2. Prüfe die rc.xml:
```bash
grep hideCursor ~/.config/labwc/rc.xml
```

3. Teste ydotool manuell:
```bash
ydotool mousemove 100 100
```

### ydotool funktioniert nicht

Prüfe die Gruppenzugehörigkeit:
```bash
groups $USER | grep input
```

Falls nicht vorhanden, führe aus und starte neu:
```bash
sudo usermod -aG input $USER
sudo reboot
```

### Chromium startet nicht

```bash
# Manuell testen (auf tty1 mit laufendem labwc)
chromium --ozone-platform=wayland --enable-features=UseOzonePlatform --kiosk https://example.com

# labwc-Log prüfen
cat /tmp/labwc.log
```

### Display geht in Standby

```bash
# wlopm manuell testen (innerhalb der Wayland-Session)
wlopm --on '*'

# User-Service-Status prüfen
systemctl --user status wlopm-keepalive

# Console Blanking prüfen
cat /proc/cmdline | grep consoleblank
```

### greetd kollidiert mit Autologin

Falls nach dem Reboot ein Login-Bildschirm (greetd/labgreeter) erscheint:
```bash
sudo systemctl disable greetd.service
sudo reboot
```

## 🔄 Deinstallation

```bash
# labwc Konfiguration entfernen
rm -rf ~/.config/labwc

# Autologin deaktivieren
sudo rm -rf /etc/systemd/system/getty@tty1.service.d/

# wlopm User-Service entfernen
rm -rf ~/.config/systemd/user/wlopm-keepalive.service
rm -rf ~/.config/systemd/user/graphical-session.target.wants/wlopm-keepalive.service

# .bash_profile labwc-Eintrag entfernen (oder Datei löschen)
# Manuell bearbeiten: nano ~/.bash_profile

# Chromium Policy entfernen
sudo rm -f /etc/chromium/policies/managed/disable_translate.json

# uinput Regel entfernen
sudo rm -f /etc/udev/rules.d/80-uinput.rules
sudo rm -f /etc/modules-load.d/uinput.conf

# ydotool entfernen (optional)
sudo rm -f /usr/local/bin/ydotool /usr/local/bin/ydotoold

# Console Blanking rückgängig machen (consoleblank=0 aus cmdline.txt entfernen)
# sudo nano /boot/firmware/cmdline.txt

sudo systemctl daemon-reload
```

## 📚 Ausführliche Dokumentation

Für eine detaillierte Schritt-für-Schritt-Anleitung, manuelle Installation und Hintergrundinformationen siehe:

**[docs/raspi-kiosk-setup.md](docs/raspi-kiosk-setup.md)**

## 📝 Lizenz

MIT License – Frei zur Verwendung und Anpassung.

---

**Erstellt für das schnelle Deployment von Raspberry Pi Kiosk-Systemen.**
