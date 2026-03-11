# Raspberry Pi Kiosk Setup

Automatisches Setup-Skript für einen Raspberry Pi Kiosk mit **Debian 13** und **labwc** (Wayland Compositor).

## 🎯 Funktionen

- **Chromium im Kiosk-Modus** - Vollbild ohne Adressleiste
- **Versteckter Cursor** - Kein Mauszeiger sichtbar
- **Display immer an** - Kein Standby/Bildschirmschoner
- **Auto-Login** - Startet automatisch beim Hochfahren
- **Übersetzung deaktiviert** - Keine Chrome-Übersetzungsdialoge

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

### Ohne URL (Standard-Platzhalter):
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Zenovs/raspi-screen/main/install.sh)"
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

# Oder ohne Parameter (nutzt Standard-Platzhalter)
sudo ./install.sh
```

### 4. System neustarten

```bash
sudo reboot
```

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
| `~/.config/labwc/autostart` | Chromium Kiosk Startskript |
| `/etc/chromium/policies/managed/disable_translate.json` | Chromium Policy |
| `/etc/systemd/system/wlopm-keepalive.service` | Display-Standby deaktiviert |

## 🔧 Troubleshooting

### Schwarzer Bildschirm nach Neustart

```bash
# Per SSH verbinden und labwc manuell starten
labwc

# Log prüfen
journalctl -xe
```

### Cursor wird trotzdem angezeigt

Prüfe die rc.xml:
```bash
cat ~/.config/labwc/rc.xml | grep hideCursor
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

### URL ändern funktioniert nicht

Stelle sicher, dass du die richtige Datei bearbeitest:
```bash
whoami  # Zeigt aktuellen Benutzer
cat /home/$(whoami)/.config/labwc/autostart
```

## 📦 Installierte Pakete

- `labwc` - Wayland Compositor
- `chromium` - Web Browser
- `wlopm` - Wayland Output Power Management
- `wlr-randr` - Display-Konfiguration
- `fonts-dejavu`, `fonts-noto` - Schriftarten

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

sudo systemctl daemon-reload
```

## 📝 Lizenz

MIT License - Frei zur Verwendung und Anpassung.

---

**Erstellt für das schnelle Deployment von Raspberry Pi Kiosk-Systemen.**
