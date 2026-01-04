# InfoMagic

InfoMagic är ett informations- och bildspelsystem för **Raspberry Pi 5**,
avsett för publika installationer med **en TV-skärm och en touchskärm**.

Systemet är byggt för att:

- starta automatiskt
- köras obemannat över lång tid
- fungera utan inloggning
- återhämta sig själv efter strömavbrott

---

## Funktioner

- Bildspel på TV (1920×1080)
- Touchskärm (Raspberry Pi Touch Display 2, porträtt)
- Touch styr bildspel (föregående / play–pause / nästa)
- Google Calendar via iframe
- SMHI-väder (5 dagar)
- Admin- och redaktörsgränssnitt
- Autostart via systemd
- TV styrs via HDMI-CEC
- Touchskärm tänds/släcks via backlight
- Schemalagd drift (t.ex. 06:00–18:00)
- Burn-in prevention via subtil pixel-shift animation
- WebSocket för realtidsuppdateringar

---

## Förutsättningar

- Raspberry Pi 5
- Raspberry Pi OS **Bookworm**
- Internetanslutning vid installation
- HDMI-TV med CEC-stöd
- Raspberry Pi Touch Display 2 (DSI)

---

## Snabbstart

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/5nine/infomagic.git
cd infomagic
sudo bash install.sh
sudo reboot
```

---

## Vad `install.sh` gör

Installationsscriptet automatiserar:

- installation av systemberoenden
- installation av Node.js-beroenden
- skapande av katalogstruktur under `/opt/infomagic`
- konfiguration av systemd-tjänster:
  - `infomagic-backend`
  - `infomagic-tv`
  - `infomagic-touch`
- konfiguration av `sudoers` för:
  - HDMI-CEC (`cec-client`)
  - touch-backlight (`tee`)

Scriptet är **idempotent** och kan köras flera gånger.

---

## Vad `install.sh` INTE gör (medvetet)

Vissa delar kräver manuell verifiering eller bör inte automatiseras:

- Konfiguration av Google Calendar-ID (görs via admin-gränssnittet)
- Kalibrering av touch-input (använd `calibrate-touch.sh` vid behov)
- Verifiering av HDMI-CEC-funktionalitet (testa manuellt efter installation)

---

## Konfiguration

InfoMagic använder följande konfigurationsfiler:

### config/config.json

Central konfiguration som läses av backend vid start och påverkar:

- bilduppladdning
- bildspel
- kalender-visning

### config/users.json

Användardata med lösenordshashar för admin och editor. Skapas automatiskt vid första installation.

---

### Touch-kalibrering

Om touch-input inte fungerar korrekt, använd kalibreringsscriptet:

```bash
./calibrate-touch.sh
```

Scriptet hjälper till att:
- Identifiera touch-enheten
- Mappa touch-input till DSI-1-displayen
- Verifiera kalibrering

---

### HDMI-CEC (TV på/av)

CEC-beteende varierar mellan TV-modeller.

Verifiera manuellt:

```bash
echo "on 0" | cec-client -s -d 1
echo "standby 0" | cec-client -s -d 1
```

Om detta inte fungerar:

- kontrollera att HDMI-CEC är aktiverat i TV:ns inställningar
- prova annan HDMI-port

---

### Skärm-mappning (HDMI vs Touch)

Standardantagande på Raspberry Pi 5:

- `wayland-0` → HDMI-A-1 (TV)
- `wayland-1` → DSI (Touch)

Verifiera med:

```bash
weston-info | grep Output
```

Om ordningen skiljer sig:

- justera `WAYLAND_DISPLAY` i:
  - `/etc/systemd/system/infomagic-tv.service`
  - `/etc/systemd/system/infomagic-touch.service`

---

### Schemaläggning (cron)

Schemaläggning installeras **automatiskt** av `install.sh` med standardtider:
- **På**: 06:00 (TV och touchskärm tänds)
- **Av**: 18:00 (TV och touchskärm släcks)

Befintliga cron jobs bevaras och uppdateras inte.

För att ändra tiderna, sätt miljövariabler innan installation:

```bash
export INFOMAGIC_ON_HOUR=7
export INFOMAGIC_ON_MINUTE=30
export INFOMAGIC_OFF_HOUR=20
export INFOMAGIC_OFF_MINUTE=0
sudo bash install.sh
```

Eller redigera manuellt efter installation:

```bash
sudo crontab -e
```

InfoMagic-cron jobs identifieras med kommentaren `# InfoMagic scheduled on/off`.

**Manuell körning av schemaläggning:**

För att manuellt köra shutdown-proceduren (samma som cronjob vid av-tid):
```bash
echo "standby 0" | sudo cec-client -s -d 1 && echo 1 | sudo tee /sys/class/backlight/*/bl_power
```

För att manuellt köra startup-proceduren (samma som cronjob vid på-tid):
```bash
# Alternativ 1: Kör fullständig startup (rekommenderas)
sudo /opt/infomagic/startup.sh

# Alternativ 2: Endast tända displayer
echo "on 0" | sudo cec-client -s -d 1
echo 0 | sudo tee /sys/class/backlight/*/bl_power
```

---

## Verifiering efter installation

Efter omstart:

```bash
systemctl status infomagic-backend
systemctl status infomagic-tv
systemctl status infomagic-touch
```

Kontrollera att:

- TV startar automatiskt
- Touchskärmen är aktiv
- Touch styr bildspelet på TV
- Nya bilder dyker upp utan omladdning
- Systemet återhämtar sig efter reboot

---

## Design & version

- TV-layout **v1.0** (låst)
- Touch-UI **v1.0** (låst)
- Admin **v1.0** (låst)
- Editor **v1.0** (låst)
- Polling: **1 sekund** (medvetet val)
- WebSocket används för realtidsuppdateringar av bildspel och bildlista

---

## API-endpoints (admin)

Följande systemkontroll-endpoints finns tillgängliga via admin-gränssnittet:

- `POST /api/system/reboot` - Starta om systemet
- `POST /api/system/tv/on` - Tänd TV via HDMI-CEC
- `POST /api/system/tv/off` - Släck TV via HDMI-CEC
- `POST /api/system/touch/on` - Tänd touchskärm (backlight)
- `POST /api/system/touch/off` - Släck touchskärm (backlight)

Alla endpoints kräver admin-roll och kan anropas via admin-gränssnittet eller direkt via API.

---

## Felsökning

### Touch-input fungerar inte

1. Kör kalibreringsscriptet: `./calibrate-touch.sh`
2. Verifiera touch-enhet: `xinput list`
3. Testa touch-input: `xinput test <device-name>`
4. Kontrollera display-mappning: `xrandr --listmonitors`

### TV startar inte automatiskt

1. Verifiera HDMI-CEC: `echo "on 0" | cec-client -s -d 1`
2. Kontrollera TV-inställningar (CEC måste vara aktiverat)
3. Prova annan HDMI-port
4. Kontrollera systemd-tjänst: `systemctl status infomagic-tv`

### Touchskärmen är svart

1. Kontrollera backlight: `cat /sys/class/backlight/*/bl_power` (ska vara 0)
2. Tänd manuellt: `echo 0 | sudo tee /sys/class/backlight/*/bl_power`
3. Kontrollera systemd-tjänst: `systemctl status infomagic-touch`
4. Kontrollera Chromium: `ps aux | grep chromium`

### Backend startar inte

1. Kontrollera systemd-tjänst: `systemctl status infomagic-backend`
2. Kontrollera loggar: `journalctl -u infomagic-backend -n 50`
3. Verifiera Node.js-beroenden: `cd /opt/infomagic/server && npm list`
4. Kontrollera port 3000: `sudo netstat -tlnp | grep 3000`

### Burn-in prevention

Systemet inkluderar automatisk burn-in prevention via CSS-animation som subtilt förskjuter innehåll med 1-2 pixlar i en cirkulär rörelse över 10 minuter. Detta är aktivt på touch-displayen och kräver ingen konfiguration.

---

## Driftfilosofi

Systemet är byggt för:

- obemannad drift
- hög stabilitet
- minimal administration
- enkel felsökning via `systemctl`
