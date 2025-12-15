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
  - `weston`
  - `infomagic-tv`
  - `infomagic-touch`
- konfiguration av `sudoers` för:
  - HDMI-CEC (`cec-client`)
  - touch-backlight (`tee`)

Scriptet är **idempotent** och kan köras flera gånger.

---

## Vad `install.sh` INTE gör (medvetet)

Vissa delar kräver manuell verifiering eller bör inte automatiseras.

---

## Konfiguration (config/config.json)

InfoMagic använder filen `config/config.json` som central konfiguration.

Filen läses av backend vid start och påverkar:
- bilduppladdning
- bildspel
- kalender-visning

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

Schemaläggning installeras **inte automatiskt** för att undvika
att skriva över befintlig crontab.

Lägg till manuellt:

```bash
crontab -e
```

Exempel (06:00–18:00):

```cron
0 6 * * * echo "on 0" | cec-client -s -d 1 && echo 1 | tee /sys/class/backlight/*/bl_power
0 18 * * * echo "standby 0" | cec-client -s -d 1 && echo 0 | tee /sys/class/backlight/*/bl_power
```

---

## Verifiering efter installation

Efter omstart:

```bash
systemctl status infomagic-backend
systemctl status weston
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

## Projektstruktur

```
infomagic/
├── install.sh
├── README.md
├── server/
│   ├── server.js
│   ├── slideshow.js
│   ├── images.js
│   ├── weather.js
│   └── config.js
├── public/
│   ├── ui/
│   │   ├── tv.html
│   │   ├── touch.html
│   │   ├── admin.html
│   │   └── editor.html
│   ├── assets/
│   │   └── sj_logo.png
│   └── images/
│       ├── originals/
│       └── thumbs/
└── package.json
```

---

## Design & version

- TV-layout **v1.0** (låst)
- Touch-UI **v1.0** (låst)
- Admin **v1.0** (låst)
- Editor **v1.0** (låst)
- Polling: **1 sekund** (medvetet val)
- WebSocket används inte i v1.0

---

## Driftfilosofi

Systemet är byggt för:
- obemannad drift
- hög stabilitet
- minimal administration
- enkel felsökning via `systemctl`
