// Entwickler-Status-Display
// ESP32 + SSD1306 (I2C) + ein Taster.
//
// Zwei Quellen bestimmen den angezeigten Status:
//   AUTOMATIK - HTTP-Endpoint wird periodisch gepollt (spaeter: Kalender, Git, ...)
//   MANUELL   - Tastendruck uebersteuert; faellt nach MANUAL_TIMEOUT_MS zurueck.
//
// Taster: kurz = naechster Status (schaltet in den manuellen Modus)
//         lang = sofort zurueck in den Automatik-Modus

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include "config.h"

// ---------------------------------------------------------------- Status-Tabelle

enum StatusId : uint8_t {
  STATUS_AVAILABLE = 0,
  STATUS_DEEP_FOCUS,
  STATUS_IN_A_CALL,
  STATUS_AWAY,
  STATUS_COUNT,
  STATUS_UNKNOWN = 255
};

struct StatusInfo {
  const char *key;    // so nennt der HTTP-Endpoint den Status
  const char *label;  // so steht er auf dem Display (CP437: \x81 == u-Umlaut)
};

static const StatusInfo STATUS_TABLE[STATUS_COUNT] = {
  { "available",  "Verf\x81gbar" },
  { "deep_focus", "Deep Focus"  },
  { "in_a_call",  "In a Call"   },
  { "away",       "Nicht da"    },
};

static StatusId statusFromKey(const String &key) {
  for (uint8_t i = 0; i < STATUS_COUNT; i++) {
    if (key.equalsIgnoreCase(STATUS_TABLE[i].key)) return static_cast<StatusId>(i);
  }
  return STATUS_UNKNOWN;
}

// ---------------------------------------------------------------- State

enum Mode : uint8_t { MODE_AUTO, MODE_MANUAL };

static Mode      mode            = MODE_AUTO;
static StatusId  autoStatus      = STATUS_UNKNOWN;  // zuletzt vom Endpoint geliefert
static StatusId  manualStatus    = STATUS_AVAILABLE;
static uint32_t  manualSince     = 0;
static bool      lastPollOk      = false;

static StatusId effectiveStatus() {
  if (mode == MODE_MANUAL) return manualStatus;
  return autoStatus;
}

// ---------------------------------------------------------------- Display

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64

static Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
static bool displayReady = false;

// Nur neu zeichnen, wenn sich etwas geaendert hat.
static StatusId drawnStatus = STATUS_UNKNOWN;
static Mode     drawnMode   = MODE_AUTO;
static int8_t   drawnMinutesLeft = -2;
static bool     drawnOnline = false;
static bool     drawnPollOk = false;
static bool     forceRedraw = true;

static int minutesLeft() {
  if (mode != MODE_MANUAL) return -1;
  uint32_t elapsed = millis() - manualSince;
  if (elapsed >= MANUAL_TIMEOUT_MS) return 0;
  return static_cast<int>((MANUAL_TIMEOUT_MS - elapsed + 59999UL) / 60000UL);
}

// Zentriert eine Zeile in der gewuenschten Textgroesse.
static void drawCentered(const char *text, uint8_t size, int16_t y) {
  int16_t bx, by;
  uint16_t bw, bh;
  display.setTextSize(size);
  display.getTextBounds(text, 0, y, &bx, &by, &bw, &bh);
  int16_t x = (SCREEN_WIDTH - static_cast<int16_t>(bw)) / 2;
  if (x < 0) x = 0;
  display.setCursor(x, y);
  display.print(text);
}

static void renderDisplay() {
  if (!displayReady) return;

  const StatusId st       = effectiveStatus();
  const bool     online   = (WiFi.status() == WL_CONNECTED);
  const int      mins     = minutesLeft();

  if (!forceRedraw && st == drawnStatus && mode == drawnMode &&
      mins == drawnMinutesLeft && online == drawnOnline && lastPollOk == drawnPollOk) {
    return;
  }
  drawnStatus = st;
  drawnMode = mode;
  drawnMinutesLeft = static_cast<int8_t>(mins > 99 ? 99 : mins);
  drawnOnline = online;
  drawnPollOk = lastPollOk;
  forceRedraw = false;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Kopfzeile: Modus links, Verbindung rechts
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print(mode == MODE_MANUAL ? "MANUELL" : "AUTO");

  const char *net = online ? (lastPollOk ? "WiFi ok" : "WiFi ??") : "offline";
  int16_t bx, by; uint16_t bw, bh;
  display.getTextBounds(net, 0, 0, &bx, &by, &bw, &bh);
  display.setCursor(SCREEN_WIDTH - static_cast<int16_t>(bw), 0);
  display.print(net);

  display.drawFastHLine(0, 11, SCREEN_WIDTH, SSD1306_WHITE);

  // Status: gross und mittig. Lange Labels werden auf Groesse 1 zurueckgestuft.
  const char *label = (st == STATUS_UNKNOWN) ? "..." : STATUS_TABLE[st].label;
  const uint8_t size = (strlen(label) <= 10) ? 2 : 1;
  drawCentered(label, size, size == 2 ? 26 : 30);

  // Fusszeile
  display.setTextSize(1);
  display.setCursor(0, 56);
  if (mode == MODE_MANUAL) {
    display.printf("noch %d min  lang=AUTO", mins);
  } else if (st == STATUS_UNKNOWN) {
    display.print("warte auf Endpoint...");
  } else {
    display.print("Taster = umschalten");
  }

  display.display();
}

static void showBootMessage(const char *msg) {
  if (!displayReady) return;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("Status-Display");
  display.println();
  display.println(msg);
  display.display();
}

// ---------------------------------------------------------------- Taster

#define DEBOUNCE_MS    50UL
#define LONG_PRESS_MS  1000UL

static bool     btnStable      = HIGH;   // entprellter Pegel (HIGH = losgelassen)
static bool     btnLastRaw     = HIGH;
static uint32_t btnLastChange  = 0;
static uint32_t btnPressedAt   = 0;
static bool     longPressFired = false;

static void enterManual(StatusId st) {
  mode = MODE_MANUAL;
  manualStatus = st;
  manualSince = millis();
  Serial.printf("[state] manuell -> %s\n", STATUS_TABLE[st].key);
}

static void enterAuto(const char *reason) {
  mode = MODE_AUTO;
  Serial.printf("[state] automatik (%s)\n", reason);
}

static void handleButton() {
  const bool raw = digitalRead(BUTTON_PIN);
  const uint32_t now = millis();

  if (raw != btnLastRaw) {
    btnLastRaw = raw;
    btnLastChange = now;
    return;
  }
  if (now - btnLastChange < DEBOUNCE_MS || raw == btnStable) {
    // Noch im Prellfenster oder keine Aenderung — nur den Long-Press pruefen.
    if (btnStable == LOW && !longPressFired && now - btnPressedAt >= LONG_PRESS_MS) {
      longPressFired = true;
      enterAuto("langer Tastendruck");
    }
    return;
  }

  btnStable = raw;
  if (raw == LOW) {                 // gedrueckt
    btnPressedAt = now;
    longPressFired = false;
  } else {                          // losgelassen
    if (!longPressFired) {
      // Kurzer Druck: naechster Status. Im Automatikmodus beim aktuellen anfangen.
      StatusId base = (mode == MODE_MANUAL) ? manualStatus
                    : (autoStatus == STATUS_UNKNOWN ? STATUS_AWAY : autoStatus);
      enterManual(static_cast<StatusId>((base + 1) % STATUS_COUNT));
    }
  }
}

// ---------------------------------------------------------------- WLAN + Polling

static uint32_t lastPollAt      = 0;
static uint32_t lastWifiCheckAt = 0;

static void wifiBegin() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.printf("[wifi] verbinde mit %s\n", WIFI_SSID);
}

// Blockiert nicht: prueft nur regelmaessig und stupst WiFi.begin() an.
static void wifiTick() {
  if (millis() - lastWifiCheckAt < 5000UL) return;
  lastWifiCheckAt = millis();

  if (WiFi.status() == WL_CONNECTED) return;
  Serial.println("[wifi] nicht verbunden, neuer Versuch");
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

// Holt den Automatik-Status vom Endpoint. Akzeptiert JSON {"status":"..."}
// oder einen reinen Text-Body mit dem Schluessel.
static void pollStatus() {
  if (WiFi.status() != WL_CONNECTED) {
    lastPollOk = false;
    return;
  }

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.setConnectTimeout(HTTP_TIMEOUT_MS);

  if (!http.begin(STATUS_URL)) {
    Serial.println("[http] begin() fehlgeschlagen (URL pruefen)");
    lastPollOk = false;
    return;
  }
  if (strlen(STATUS_TOKEN) > 0) {
    http.addHeader("Authorization", String("Bearer ") + STATUS_TOKEN);
  }

  const int code = http.GET();
  if (code != HTTP_CODE_OK) {
    Serial.printf("[http] GET %s -> %d\n", STATUS_URL, code);
    lastPollOk = false;
    http.end();
    return;
  }

  String body = http.getString();
  http.end();
  body.trim();

  String key;
  JsonDocument doc;
  if (deserializeJson(doc, body) == DeserializationError::Ok && doc["status"].is<const char *>()) {
    key = doc["status"].as<const char *>();
  } else {
    key = body;   // Fallback: reiner Text
  }
  key.trim();

  const StatusId st = statusFromKey(key);
  if (st == STATUS_UNKNOWN) {
    Serial.printf("[http] unbekannter Status '%s'\n", key.c_str());
    lastPollOk = false;
    return;
  }

  lastPollOk = true;
  if (st != autoStatus) {
    autoStatus = st;
    Serial.printf("[http] automatik -> %s\n", STATUS_TABLE[st].key);
  }
}

// ---------------------------------------------------------------- setup / loop

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n[boot] Entwickler-Status-Display");

  pinMode(BUTTON_PIN, INPUT_PULLUP);

  Wire.begin(I2C_SDA, I2C_SCL);
  displayReady = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
  if (!displayReady) {
    Serial.println("[oled] nicht gefunden - Adresse/Verkabelung pruefen");
  } else {
    display.cp437(true);   // Umlaute im Standardfont (\x81 == u-Umlaut)
    showBootMessage("WLAN...");
  }

  wifiBegin();
  lastPollAt = millis() - POLL_INTERVAL_MS;   // erster Poll sofort
}

void loop() {
  handleButton();
  wifiTick();

  if (mode == MODE_MANUAL && millis() - manualSince >= MANUAL_TIMEOUT_MS) {
    enterAuto("Timeout");
  }

  if (millis() - lastPollAt >= POLL_INTERVAL_MS) {
    lastPollAt = millis();
    pollStatus();
  }

  renderDisplay();
  delay(5);
}
