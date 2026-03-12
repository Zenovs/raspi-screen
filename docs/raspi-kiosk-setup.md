# sicht!bar Screen – Raspberry Pi Kiosk-Setup

**Debian 13 / rpd-labwc / Wayland**

Diese Dokumentation beschreibt, wie ein Raspberry Pi mit Debian 13 (Trixie) und rpd‑labwc so konfiguriert wird, dass:

- Eine statische WLAN-IP verwendet wird
- Beim Booten automatisch Chromium im Kiosk-Modus mit einer bestimmten URL startet
- Bildschirmschoner / Standby deaktiviert sind
- Der Mauszeiger ausgeblendet wird, indem er einmal automatisch bewegt wird (Trigger für Webflow-Regel)
- Chromium keine Übersetzungsleiste für Englisch anbietet

**Beispiel Ziel-URL:**
```
https://schnyder.webflow.io/screens/sichtbar-screen
```

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

## 2. Boot-Ziel: Grafische Oberfläche und Autologin

Damit der Kiosk-Modus funktioniert, muss das System automatisch in die grafische Oberfläche booten.

### Prüfen, ob das grafische Target aktiv ist:

```bash
systemctl get-default
```

### Falls nicht `graphical.target`:

```bash
sudo systemctl set-default graphical.target
```

### Autologin in den Desktop aktivieren:

```bash
sudo raspi-config
```

1. **System Options** → **Boot / Auto Login**
2. **Desktop Autologin** auswählen
3. Beenden und neu starten

---

## 3. Chromium installieren (falls nicht vorhanden)

```bash
sudo apt update
sudo apt install chromium -y
```

**Browser-Binary:** `/usr/bin/chromium`

---

## 4. Kiosk-Autostart mit labwc einrichten

labwc liest beim Start die Datei `~/.config/labwc/autostart`.

### Verzeichnis anlegen:

```bash
mkdir -p ~/.config/labwc
```

### Autostart-Datei bearbeiten:

```bash
nano ~/.config/labwc/autostart
```

### Inhalt (finale, funktionierende Version):

```bash
# Bildschirmschoner und Standby deaktivieren
wlopm --set-standby off

# ydotool Daemon starten, um später die Maus zu bewegen
ydotoold &

# 50 Sekunden warten, bis System und Chromium komplett geladen sind,
# dann Maus um 100 Pixel bewegen, damit die Webflow-Regel den Cursor versteckt
(sleep 50 && ydotool mousemove 100 100) &

# Chromium im Kiosk- und Inkognito-Modus starten
# Übersetzungsfunktionen soweit wie möglich deaktivieren
chromium \
  --kiosk \
  --incognito \
  --noerrdialogs \
  --disable-infobars \
  --no-first-run \
  --password-store=basic \
  --disable-translate \
  --disable-features=Translate,TranslateUI,LanguageDetection,TranslateSettings \
  --start-maximized \
  "https://schnyder.webflow.io/screens/sichtbar-screen" &
```

### Hinweise:

- `--incognito` stellt sicher, dass keine persistenten Daten/Popups zwischen Starts überleben.
- Die `Translate*`-Flags reduzieren die Wahrscheinlichkeit, dass Chromium den Übersetzungsbalken einblendet.
- Der eigentliche „Ausblendeffekt" für den Cursor passiert über die Website (Webflow), sobald Mausbewegung erkannt wird.

---

## 5. Mausbewegung automatisieren mit ydotool (Wayland-kompatibel)

Unter Wayland funktioniert `xdotool` nicht. Stattdessen wird `ydotool` verwendet.

### 5.1. Abhängigkeiten installieren

```bash
sudo apt install cmake libevdev-dev git scdoc -y
```

### 5.2. ydotool aus den Quellen bauen und installieren

```bash
cd ~
git clone https://github.com/ReimuNotMoe/ydotool.git
cd ydotool
mkdir build
cd build
cmake ..
make
sudo make install
```

Damit werden `ydotool` und `ydotoold` unter `/usr/local/bin/` installiert.

### 5.3. Zugriffsrechte für /dev/uinput (Eingabeemulation)

Chromium läuft als Benutzer. Dieser Benutzer braucht Rechte, um Eingaben zu emulieren.

```bash
sudo usermod -aG input $USER
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/80-uinput.rules
```

**Anschliessend ist ein Neustart erforderlich, damit die Gruppenänderung aktiv wird.**

---

## 6. Labwc-Mauskonfiguration (optional)

Zusätzlich kann labwc angewiesen werden, den Cursor grundsätzlich zu verstecken. Das ist optional, da im Setup die Webflow-Regel das eigentliche Verstecken übernimmt.

```bash
nano ~/.config/labwc/rc.xml
```

**Inhalt:**

```xml
<labwc_config>
  <mouse>
    <hideCursor>true</hideCursor>
  </mouse>
</labwc_config>
```

---

## 7. Verhalten nach dem Boot

### Ablauf nach einem Neustart:

1. System bootet in `graphical.target`.
2. Benutzer wird automatisch in die rpd‑labwc Session eingeloggt.
3. `~/.config/labwc/autostart` wird ausgeführt:
   - `wlopm --set-standby off` deaktiviert Standby/Bildschirmschoner.
   - `ydotoold` startet im Hintergrund und stellt einen Eingabe-Socket bereit.
   - `sleep 50 && ydotool mousemove 100 100` bewegt nach 50 Sekunden die Maus.
   - Chromium startet im Kiosk-/Inkognito-Modus mit der Bildschirm-URL.
4. Wenn Chromium und die Seite vollständig geladen sind, wird nach 50s eine Mausbewegung simuliert.
5. Die Webflow-Logik („Maus ausblenden nach Inaktivität") erkennt zuerst Bewegung, dann Inaktivität und blendet den Cursor aus.
6. **Nutzer sehen nur die Webflow-Seite im Vollbild, ohne Taskleiste, ohne Adressleiste, ohne Mauszeiger.**

---

## 8. Bekannte Einschränkungen und Hinweise

### Übersetzungsleiste

Trotz der Flags kann Chromium bei Seiten, die als `lang="en"` deklariert sind, gelegentlich einen Übersetzungsbalken zeigen.

**Empfohlene Ergänzung auf Webflow-Seite:**
- Das HTML-lang-Attribut für diese Screen-Seite auf `de` oder `de-CH` setzen, um die Wahrscheinlichkeit weiter zu reduzieren.

### ydotool Wartung

- Falls `ydotool` oder `ydotoold` in einer späteren Debian-Version paketiert wird, könnte man das manuelle Build ersetzen.
- Das Install-Skript automatisiert die Schritte aus Kapitel 5.

### Anpassungen für andere Screens / URLs

- Nur die URL in der Autostart-Zeile anpassen.
- IP-/Gateway-Werte in Abschnitt 1 an das jeweilige Netzwerk anpassen.

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
3. Konfiguriert uinput-Zugriffsrechte
4. Setzt graphical.target als Standard
5. Erstellt labwc Konfiguration
6. Konfiguriert Chromium Policies
7. Richtet Autologin ein
8. (Optional) Konfiguriert statische IP

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
