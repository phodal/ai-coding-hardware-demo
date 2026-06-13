#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <WiFi.h>
#include <Wire.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

String inputLine;
bool displayReady = false;
bool radioReady = false;
bool connected = false;
uint32_t frame = 0;
uint32_t scanCount = 0;
uint32_t joinCount = 0;
int lastNetworkCount = -1;
int lastBestRssi = -127;
uint32_t lastScanMs = 0;
String lastIp = "0.0.0.0";

void centerText(const char *text, int16_t y, uint8_t size, uint16_t color) {
  int16_t x1;
  int16_t y1;
  uint16_t w;
  uint16_t h;
  gfx->setTextSize(size);
  gfx->getTextBounds(text, 0, y, &x1, &y1, &w, &h);
  gfx->setCursor((LCD_WIDTH - w) / 2, y);
  gfx->setTextColor(color, RGB565_BLACK);
  gfx->print(text);
}

void drawWifiScreen(const char *status) {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, RGB565_CYAN);
  centerText("WIFI", 42, 7, RGB565_YELLOW);
  centerText(status, 130, 8, radioReady ? RGB565_WHITE : RGB565_RED);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_GREEN, RGB565_BLACK);
  gfx->setCursor(42, 282);
  gfx->print("AP count ");
  gfx->print(lastNetworkCount);

  gfx->setCursor(42, 318);
  gfx->print("Best RSSI ");
  gfx->print(lastBestRssi);

  gfx->setCursor(42, 354);
  gfx->print("Connected ");
  gfx->print(connected ? "yes" : "no");

  gfx->setCursor(42, 390);
  gfx->print("IP ");
  gfx->print(lastIp);
}

void emitState() {
  connected = WiFi.status() == WL_CONNECTED;
  lastIp = connected ? WiFi.localIP().toString() : "0.0.0.0";

  Serial.print("WIFI_STATE display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" radio=");
  Serial.print(radioReady ? 1 : 0);
  Serial.print(" connected=");
  Serial.print(connected ? 1 : 0);
  Serial.print(" scan_count=");
  Serial.print(scanCount);
  Serial.print(" join_count=");
  Serial.print(joinCount);
  Serial.print(" last_count=");
  Serial.print(lastNetworkCount);
  Serial.print(" best_rssi=");
  Serial.print(lastBestRssi);
  Serial.print(" ip=");
  Serial.println(lastIp);
  Serial.flush();
}

void runScan(const char *source) {
  if (!radioReady) {
    Serial.print("WIFI_SCAN status=radio_failed source=");
    Serial.println(source);
    Serial.flush();
    drawWifiScreen("WAIT");
    return;
  }

  drawWifiScreen("SCAN");
  WiFi.scanDelete();
  uint32_t startMs = millis();
  int networks = WiFi.scanNetworks(false, true);
  lastScanMs = millis() - startMs;
  scanCount++;
  lastNetworkCount = networks;
  lastBestRssi = -127;

  if (networks >= 0) {
    int limit = min(networks, 5);
    for (int i = 0; i < limit; i++) {
      int rssi = WiFi.RSSI(i);
      lastBestRssi = max(lastBestRssi, rssi);
      Serial.print("WIFI_AP index=");
      Serial.print(i);
      Serial.print(" rssi=");
      Serial.print(rssi);
      Serial.print(" channel=");
      Serial.print(WiFi.channel(i));
      Serial.print(" enc=");
      Serial.println(static_cast<int>(WiFi.encryptionType(i)));
    }
  }

  Serial.print("WIFI_SCAN status=");
  Serial.print(networks >= 0 ? "ok" : "failed");
  Serial.print(" source=");
  Serial.print(source);
  Serial.print(" count=");
  Serial.print(networks);
  Serial.print(" best_rssi=");
  Serial.print(lastBestRssi);
  Serial.print(" elapsed_ms=");
  Serial.print(lastScanMs);
  Serial.print(" scan_count=");
  Serial.println(scanCount);
  Serial.flush();

  drawWifiScreen(networks >= 0 ? "OK" : "FAIL");
  WiFi.scanDelete();
}

void joinNetwork(String payload) {
  payload.trim();
  int comma = payload.indexOf(',');
  if (comma <= 0) {
    Serial.println("WIFI_JOIN status=invalid_request connected=0");
    Serial.flush();
    return;
  }

  String ssid = payload.substring(0, comma);
  String password = payload.substring(comma + 1);
  ssid.trim();
  password.trim();
  joinCount++;
  drawWifiScreen("JOIN");

  WiFi.disconnect(true, true);
  delay(200);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  uint32_t deadline = millis() + 15000;
  while (WiFi.status() != WL_CONNECTED && millis() < deadline) {
    delay(250);
  }

  connected = WiFi.status() == WL_CONNECTED;
  lastIp = connected ? WiFi.localIP().toString() : "0.0.0.0";
  Serial.print("WIFI_JOIN status=");
  Serial.print(connected ? "ok" : "failed");
  Serial.print(" connected=");
  Serial.print(connected ? 1 : 0);
  Serial.print(" rssi=");
  Serial.print(connected ? WiFi.RSSI() : -127);
  Serial.print(" ip=");
  Serial.print(lastIp);
  Serial.print(" join_count=");
  Serial.println(joinCount);
  Serial.flush();

  drawWifiScreen(connected ? "JOIN OK" : "JOIN NO");
}

void handleCommand(String line) {
  line.trim();
  if (line.length() == 0) {
    return;
  }

  if (line == "PING") {
    Serial.println("PONG");
    Serial.flush();
  } else if (line == "SCAN") {
    runScan("serial");
  } else if (line == "STATUS?") {
    emitState();
  } else if (line.startsWith("JOIN:")) {
    joinNetwork(line.substring(5));
  } else if (line == "DISCONNECT") {
    WiFi.disconnect(true, true);
    connected = false;
    lastIp = "0.0.0.0";
    Serial.println("WIFI_DISCONNECT status=ok connected=0");
    Serial.flush();
    drawWifiScreen("OK");
  } else {
    Serial.print("WIFI_ERROR unknown_command=");
    Serial.println(line.substring(0, 48));
    Serial.flush();
  }
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("wifi_connectivity_probe boot");
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  if (gfx->begin()) {
    gfx->setBrightness(200);
    gfx->setRotation(DISPLAY_ROTATION);
    displayReady = true;
  } else {
    Serial.println("WIFI_DISPLAY_FAILED");
    Serial.flush();
  }

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false, true);
  radioReady = true;
  drawWifiScreen("READY");
  Serial.println("WIFI_READY display=1 radio=1");
  emitState();
  runScan("boot");
}

void loop() {
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      handleCommand(inputLine);
      inputLine = "";
    } else if (c != '\r') {
      inputLine += c;
      if (inputLine.length() > 192) {
        inputLine = inputLine.substring(inputLine.length() - 192);
      }
    }
  }

  if ((frame % 200) == 0) {
    emitState();
  }
  frame++;
  delay(50);
}
