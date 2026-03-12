# Raspberry Pi Kiosk Setup

Automatisches Setup-Skript für einen Raspberry Pi Kiosk mit **Debian 13** und **labwc** (Wayland Compositor).

## 🎯 Funktionen

- **Chromium im Kiosk-Modus** - Vollbild ohne Adressleiste, Inkognito-Modus
- **Versteckter Cursor** - Kein Mauszeiger sichtbar (via ydotool + Webflow-Logik)
- **Display immer an** - Kein Standby/Bildschirmschoner
- **Auto-Login** - Startet automatisch beim Hochfahren
- **Übersetzung deaktiviert** - Keine Chrome-Übersetzungsdialoge
- **Automatische Mausbewegung** - Triggert Cursor-Hider via ydotool
- **Optionale statische IP** - Netzwerkkonfiguration via nmcli

## 📋 Systemanforderungen

- Raspberry Pi (3, 4 oder 5)
- **Debian 13** mit labwc (Raspberry Pi OS Wayland)
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

> ⚠️ **Wichtig:** Ein Neustart ist erforderlich, damit die uinput-Gruppenrechte für ydotool aktiv werden!

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
| `/etc/chromium/policies/managed/disable_translate.json` | Chromium Policy |
| `/etc/systemd/system/wlopm-keepalive.service` | Display-Standby deaktiviert |
| `/etc/udev/rules.d/80-uinput.rules` | uinput-Zugriffsrechte für ydotool |
| `/usr/local/bin/ydotool` | ydotool Binary |
| `/usr/local/bin/ydotoold` | ydotool Daemon |

## 📦 Installierte Pakete

- `labwc` - Wayland Compositor
- `chromium` - Web Browser
- `wlopm` - Wayland Output Power Management
- `wlr-randr` - Display-Konfiguration
- `cmake`, `libevdev-dev`, `git`, `scdoc` - Build-Dependencies für ydotool
- `fonts-dejavu`, `fonts-noto` - Schriftarten

## 🔧 Troubleshooting

### Schwarzer Bildschirm nach Neustart

```bash
# Per SSH verbinden und labwc manuell starten
labwc

# Log prüfen
journalctl -xe
```

### Cursor wird trotzdem angezeigt

1. Prüfe ob ydotool läuft:
```bash
ps aux | grep ydotool
```

2. Prüfe die rc.xml:
```bash
cat ~/.config/labwc/rc.xml | grep hideCursor
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
# Manuell testen
chromium --kiosk https://example.com

# Logs prüfen
journalctl -u wlopm-keepalive
```

### Display geht in Standby

```bash
# Service-Status prüfen
sudo systemctl status wlopm-keepalive

# Service neu starten
sudo systemctl restart wlopm-keepalive
```

## 🔄 Deinstallation

```bash
# labwc Konfiguration entfernen
rm -rf ~/.config/labwc

# Autologin deaktivieren
sudo rm /etc/systemd/system/getty@tty1.service.d/autologin.conf

# wlopm Service deaktivieren
sudo systemctl disable wlopm-keepalive
sudo rm /etc/systemd/system/wlopm-keepalive.service

# Chromium Policy entfernen
sudo rm /etc/chromium/policies/managed/disable_translate.json

# uinput Regel entfernen
sudo rm /etc/udev/rules.d/80-uinput.rules

# ydotool entfernen (optional)
sudo rm /usr/local/bin/ydotool /usr/local/bin/ydotoold

sudo systemctl daemon-reload
```

## 📚 Ausführliche Dokumentation

Für eine detaillierte Schritt-für-Schritt-Anleitung, manuelle Installation und Hintergrundinformationen siehe:

**[docs/raspi-kiosk-setup.md](docs/raspi-kiosk-setup.md)**

## 📝 Lizenz

MIT License - Frei zur Verwendung und Anpassung.

---

**Erstellt für das schnelle Deployment von Raspberry Pi Kiosk-Systemen.**

*Beispiel-URL: https://i.ytimg.com/vi/lXMOppp4byE/hqdefault.jpg
