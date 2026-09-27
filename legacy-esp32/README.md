# status-display

> **Archiv.** Diese ESP32-Firmware ist seit 27.09.2026 abgelöst durch die
> Mac-App im Repo-Wurzelverzeichnis. Sie bleibt hier unverändert liegen.

Ein kleines ESP32-Gerät für den Schreibtisch: das OLED zeigt an, ob gerade
"Deep Focus", "In a Call" oder "Verfügbar" gilt. Der Status kommt normalerweise
automatisch von einem HTTP-Endpoint (später z.B. aus Kalender oder Git-Aktivität)
und lässt sich per Taster jederzeit von Hand übersteuern.

## Verhalten

| Zustand | Beschreibung |
|---|---|
| **AUTO** | Gerät pollt `STATUS_URL` alle 30 s und zeigt, was der Endpoint sagt. |
| **MANUELL** | Ein kurzer Tastendruck schaltet zum nächsten Status und friert ihn ein. |
| **Rückfall** | Nach 30 min ohne Tastendruck geht es automatisch zurück auf AUTO. Ein langer Druck (≥ 1 s) tut das sofort. |

Statuswerte: `available`, `deep_focus`, `in_a_call`, `away` — definiert in
`STATUS_TABLE` in [src/main.cpp](src/main.cpp).

## Hardware

| Teil | Hinweis |
|---|---|
| ESP32 DevKit v1 (30- oder 38-Pin) | `board = esp32dev` |
| OLED SSD1306, 0.96", 128×64, I2C | 4 Pins (VCC/GND/SCL/SDA), Adresse meist `0x3C` |
| Taster (Momentary, 6 mm) | gegen GND; interner Pull-up wird genutzt |
| Breadboard + Jumper (m/m) | ca. 6 Kabel |
| USB-Kabel (Micro-USB bzw. USB-C je nach Board) | Strom + Flashen |

Optional: 100 nF Kondensator parallel zum Taster als Hardware-Entprellung —
nötig ist er nicht, die Software entprellt bereits.

### Verdrahtung

```
OLED VCC  -> ESP32 3V3
OLED GND  -> ESP32 GND
OLED SDA  -> ESP32 GPIO21
OLED SCL  -> ESP32 GPIO22

Taster Pin A -> ESP32 GPIO0
Taster Pin B -> ESP32 GND
```

GPIO0 ist auf den meisten DevKits der BOOT-Taster — man kann also erst einmal
ganz ohne externen Taster testen. Achtung: GPIO0 muss beim Reset HIGH sein,
also den Taster beim Booten nicht gedrückt halten. Wer das vermeiden will,
setzt `BUTTON_PIN` in `config.h` z.B. auf `GPIO4`.

Pins lassen sich in `src/config.h` ändern (`BUTTON_PIN`, `I2C_SDA`, `I2C_SCL`).

## Setup

1. **PlatformIO installieren** (VS Code-Extension oder CLI):
   ```bash
   pip install -U platformio
   ```

2. **Konfiguration anlegen** — `src/config.h` steht in `.gitignore` und wird
   nie committet:
   ```bash
   cp src/config.h.example src/config.h
   ```
   Dann WLAN-Zugangsdaten und `STATUS_URL` eintragen.

3. **Bauen und flashen** (ESP32 per USB angeschlossen):
   ```bash
   pio run -t upload
   ```

4. **Log ansehen:**
   ```bash
   pio device monitor
   ```

## Endpoint-Vertrag

Das Gerät macht ein `GET` auf `STATUS_URL` und erwartet HTTP 200 mit entweder

```json
{"status": "deep_focus"}
```

oder einem reinen Text-Body:

```
deep_focus
```

Ist `STATUS_TOKEN` in `config.h` gesetzt, wird `Authorization: Bearer <token>`
mitgeschickt. Unbekannte Werte werden ignoriert (der letzte gültige Status
bleibt stehen, das Display zeigt `WiFi ??`).

Zum Ausprobieren reicht ein Einzeiler auf dem Rechner:

```bash
printf 'deep_focus' > status.txt && python3 -m http.server 8080
```

`STATUS_URL` dann auf `http://<rechner-ip>:8080/status.txt` setzen.

## Dateien

- [platformio.ini](platformio.ini) — Board, Libraries, Build-Flags
- [src/main.cpp](src/main.cpp) — Display, Taster-Entprellung, State-Machine, HTTP-Polling
- [src/config.h.example](src/config.h.example) — Vorlage für die lokale `config.h`

## Nächste Schritte

- HTTPS statt HTTP, sobald der Endpoint außerhalb des LANs liegt
- Endpoint anbinden (Kalender-Freebusy, `git`-Aktivität, Meeting-Tool)
- Deep Sleep zwischen den Polls, falls das Gerät auf Akku laufen soll
