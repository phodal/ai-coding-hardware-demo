#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <HTTPClient.h>
#include <TouchDrvCSTXXX.hpp>
#include <WiFi.h>
#include <Wire.h>
#include <string.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

#ifndef DISPLAY_BRIGHTNESS
#define DISPLAY_BRIGHTNESS 96
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

TouchDrvCST92xx touch;

constexpr int16_t BUTTON_X = 54;
constexpr int16_t BUTTON_Y = 154;
constexpr int16_t BUTTON_W = 360;
constexpr int16_t BUTTON_H = 126;

String inputLine;
String wifiSsid;
String wifiPassword;
String aiEndpoint;
String lastResponse = "Ready";
String lastError = "";

bool displayReady = false;
bool touchReady = false;
bool wifiReady = false;
uint32_t triggerCount = 0;
uint32_t touchCount = 0;
uint32_t frame = 0;
uint32_t lastTouchMs = 0;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};

void centerText(const String &text, int16_t y, uint8_t size, uint16_t color, uint16_t bg = RGB565_BLACK) {
  int16_t x1;
  int16_t y1;
  uint16_t w;
  uint16_t h;
  gfx->setTextSize(size);
  gfx->getTextBounds(text.c_str(), 0, y, &x1, &y1, &w, &h);
  gfx->setCursor(max<int16_t>(0, (LCD_WIDTH - w) / 2), y);
  gfx->setTextColor(color, bg);
  gfx->print(text);
}

String clipped(const String &text, size_t limit) {
  if (text.length() <= limit) {
    return text;
  }
  return text.substring(0, limit - 3) + "...";
}

void drawWrapped(const String &text, int16_t x, int16_t y, uint8_t size, uint16_t color) {
  gfx->setTextSize(size);
  gfx->setTextColor(color, RGB565_BLACK);
  String value = clipped(text, 72);
  int line = 0;
  while (value.length() > 0 && line < 3) {
    int take = min<int>(24, value.length());
    int split = take;
    if (value.length() > take) {
      int space = value.lastIndexOf(' ', take);
      if (space > 8) {
        split = space;
      }
    }
    gfx->setCursor(x, y + line * 30);
    gfx->print(value.substring(0, split));
    value = value.substring(split);
    value.trim();
    line++;
  }
}

void drawScreen(const char *status, uint16_t statusColor = RGB565_WHITE) {
  if (!displayReady) {
    return;
  }
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRoundRect(14, 14, LCD_WIDTH - 28, LCD_HEIGHT - 28, 22, RGB565_BLUE);

  if (strcmp(status, "AI OK") == 0) {
    centerText("Qoder", 50, 6, RGB565_CYAN);
    centerText("OK", 136, 9, RGB565_WHITE);
    centerText("AI OK", 238, 3, RGB565_GREEN);
    drawWrapped(lastResponse, 54, 304, 2, RGB565_WHITE);
    gfx->setTextSize(2);
    gfx->setTextColor(wifiReady ? RGB565_GREEN : RGB565_YELLOW, RGB565_BLACK);
    gfx->setCursor(54, 396);
    gfx->print("WiFi ");
    gfx->print(wifiReady ? "ready" : "missing");
    return;
  }

  centerText("Qoder", 42, 6, RGB565_CYAN);
  centerText("OK", 104, 5, RGB565_WHITE);

  gfx->fillRoundRect(BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 22, RGB565_GREEN);
  gfx->drawRoundRect(BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 22, RGB565_WHITE);
  if (strcmp(status, "AI OK") == 0) {
    centerText("Qoder", BUTTON_Y + 22, 5, RGB565_BLACK, RGB565_GREEN);
    centerText("OK", BUTTON_Y + 78, 4, RGB565_BLACK, RGB565_GREEN);
  } else {
    centerText("ASK AI", BUTTON_Y + 38, 5, RGB565_BLACK, RGB565_GREEN);
  }

  gfx->setTextSize(2);
  gfx->setTextColor(statusColor, RGB565_BLACK);
  gfx->setCursor(42, 304);
  gfx->print("Status: ");
  gfx->print(status);

  gfx->setCursor(42, 336);
  gfx->setTextColor(wifiReady ? RGB565_GREEN : RGB565_YELLOW, RGB565_BLACK);
  gfx->print("WiFi: ");
  gfx->print(wifiReady ? WiFi.localIP().toString() : "not connected");

  gfx->setCursor(42, 368);
  gfx->setTextColor(touchReady ? RGB565_GREEN : RGB565_YELLOW, RGB565_BLACK);
  gfx->print("Touch: ");
  gfx->print(touchReady ? "ready" : "missing");

  drawWrapped(lastError.length() ? lastError : lastResponse, 42, 400, 2, lastError.length() ? RGB565_RED : RGB565_WHITE);
}

void emitState() {
  wifiReady = WiFi.status() == WL_CONNECTED;
  Serial.print("WEB_AI_STATE display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" wifi=");
  Serial.print(wifiReady ? 1 : 0);
  Serial.print(" triggers=");
  Serial.print(triggerCount);
  Serial.print(" touches=");
  Serial.print(touchCount);
  Serial.print(" ip=");
  Serial.println(wifiReady ? WiFi.localIP().toString() : "0.0.0.0");
  Serial.flush();
}

String urlEncode(const String &value) {
  const char *hex = "0123456789ABCDEF";
  String out;
  out.reserve(value.length() + 8);
  for (size_t i = 0; i < value.length(); i++) {
    uint8_t c = static_cast<uint8_t>(value[i]);
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
      out += static_cast<char>(c);
    } else if (c == ' ') {
      out += '+';
    } else {
      out += '%';
      out += hex[(c >> 4) & 0x0F];
      out += hex[c & 0x0F];
    }
  }
  return out;
}

String extractJsonField(const String &body, const char *field) {
  String needle = String("\"") + field + "\":";
  int start = body.indexOf(needle);
  if (start < 0) {
    return "";
  }
  start += needle.length();
  while (start < static_cast<int>(body.length()) && body[start] == ' ') {
    start++;
  }
  if (start >= static_cast<int>(body.length()) || body[start] != '"') {
    return "";
  }
  start++;
  String out;
  bool escaping = false;
  for (int i = start; i < static_cast<int>(body.length()); i++) {
    char c = body[i];
    if (escaping) {
      out += c;
      escaping = false;
    } else if (c == '\\') {
      escaping = true;
    } else if (c == '"') {
      return out;
    } else {
      out += c;
    }
  }
  return out;
}

void connectWifi(const String &ssid, const String &password) {
  wifiSsid = ssid;
  wifiPassword = password;
  wifiSsid.trim();
  wifiPassword.trim();

  drawScreen("WiFi join", RGB565_YELLOW);
  if (WiFi.status() == WL_CONNECTED && WiFi.SSID() == wifiSsid) {
    wifiReady = true;
    Serial.print("WEB_AI_WIFI status=ok connected=1 rssi=");
    Serial.print(WiFi.RSSI());
    Serial.print(" ip=");
    Serial.println(WiFi.localIP().toString());
    Serial.flush();
    drawScreen("Ready", RGB565_GREEN);
    return;
  }

  WiFi.disconnect(false, true);
  delay(200);
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());

  uint32_t deadline = millis() + 18000;
  while (WiFi.status() != WL_CONNECTED && millis() < deadline) {
    delay(250);
  }

  wifiReady = WiFi.status() == WL_CONNECTED;
  Serial.print("WEB_AI_WIFI status=");
  Serial.print(wifiReady ? "ok" : "failed");
  Serial.print(" connected=");
  Serial.print(wifiReady ? 1 : 0);
  Serial.print(" rssi=");
  Serial.print(wifiReady ? WiFi.RSSI() : -127);
  Serial.print(" ip=");
  Serial.println(wifiReady ? WiFi.localIP().toString() : "0.0.0.0");
  Serial.flush();
  drawScreen(wifiReady ? "Ready" : "WiFi failed", wifiReady ? RGB565_GREEN : RGB565_RED);
}

bool configureFromPayload(String payload) {
  int first = payload.indexOf(',');
  int second = payload.indexOf(',', first + 1);
  if (first <= 0 || second <= first) {
    Serial.println("WEB_AI_CONFIG status=invalid");
    Serial.flush();
    return false;
  }
  aiEndpoint = payload.substring(second + 1);
  aiEndpoint.trim();
  Serial.print("WEB_AI_CONFIG status=ok endpoint=");
  Serial.println(aiEndpoint);
  Serial.flush();
  connectWifi(payload.substring(0, first), payload.substring(first + 1, second));
  return wifiReady;
}

void triggerAi(const char *source, String prompt) {
  prompt.trim();
  if (prompt.length() == 0) {
    prompt = "button pressed";
  }
  triggerCount++;
  lastError = "";
  lastResponse = "Thinking";
  drawScreen("AI request", RGB565_YELLOW);
  Serial.print("WEB_AI_TRIGGER source=");
  Serial.print(source);
  Serial.print(" count=");
  Serial.print(triggerCount);
  Serial.print(" prompt_chars=");
  Serial.println(prompt.length());
  Serial.flush();

  if (WiFi.status() != WL_CONNECTED) {
    wifiReady = false;
    lastError = "WiFi not connected";
    Serial.println("WEB_AI_RESPONSE status=wifi_missing code=0 text=");
    Serial.flush();
    drawScreen("No WiFi", RGB565_RED);
    return;
  }
  if (aiEndpoint.length() == 0) {
    lastError = "Endpoint missing";
    Serial.println("WEB_AI_RESPONSE status=endpoint_missing code=0 text=");
    Serial.flush();
    drawScreen("No endpoint", RGB565_RED);
    return;
  }

  String requestUrl = aiEndpoint;
  requestUrl += aiEndpoint.indexOf('?') >= 0 ? "&" : "?";
  requestUrl += "question=";
  requestUrl += urlEncode(prompt);
  requestUrl += "&source=esp32-web-ai-button";

  int code = -1;
  String body = "";
  for (int attempt = 1; attempt <= 3; attempt++) {
    HTTPClient http;
    http.setConnectTimeout(4000);
    http.setTimeout(8000);
    http.begin(requestUrl);
    code = http.GET();
    body = code > 0 ? http.getString() : "";
    http.end();
    if (code >= 200 && code < 300) {
      break;
    }
    Serial.print("WEB_AI_HTTP_RETRY attempt=");
    Serial.print(attempt);
    Serial.print(" code=");
    Serial.println(code);
    Serial.flush();
    delay(500);
  }

  if (code < 200 || code >= 300) {
    lastError = String("HTTP ") + code;
    Serial.print("WEB_AI_RESPONSE status=http_error code=");
    Serial.print(code);
    Serial.println(" text=");
    Serial.flush();
    drawScreen("HTTP fail", RGB565_RED);
    return;
  }

  String answer = extractJsonField(body, "text");
  if (answer.length() == 0) {
    answer = extractJsonField(body, "response");
  }
  if (answer.length() == 0) {
    answer = extractJsonField(body, "answer");
  }
  if (answer.length() == 0) {
    answer = body;
  }
  answer.replace('\n', ' ');
  answer.replace('\r', ' ');
  answer.trim();
  lastResponse = clipped(answer, 100);
  Serial.print("WEB_AI_RESPONSE status=ok code=");
  Serial.print(code);
  Serial.print(" chars=");
  Serial.print(lastResponse.length());
  Serial.print(" text=");
  Serial.println(lastResponse);
  Serial.flush();
  drawScreen("AI OK", RGB565_GREEN);
}

void handleCommand(String line) {
  line.trim();
  if (line.length() == 0) {
    return;
  }
  if (line == "PING") {
    Serial.println("PONG");
    Serial.flush();
  } else if (line == "STATE?") {
    emitState();
  } else if (line.startsWith("CONFIG:")) {
    configureFromPayload(line.substring(7));
  } else if (line.startsWith("TRIGGER:")) {
    triggerAi("serial", line.substring(8));
  } else if (line == "TRIGGER") {
    triggerAi("serial", "button pressed");
  } else {
    Serial.print("WEB_AI_ERROR unknown_command=");
    Serial.println(line.substring(0, 48));
    Serial.flush();
  }
}

void resetTouchPins() {
  pinMode(TP_RST, OUTPUT);
  digitalWrite(TP_RST, LOW);
  delay(30);
  digitalWrite(TP_RST, HIGH);
  delay(150);
}

void setupTouch() {
  resetTouchPins();
  touch.setPins(TP_RST, TP_INT);
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!touchReady) {
    Serial.println("WEB_AI_TOUCH_FAILED");
    Serial.flush();
    return;
  }
  touch.reset();
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setMirrorXY(true, true);
  Serial.print("WEB_AI_TOUCH_READY model=");
  Serial.print(touch.getModelName());
  Serial.print(" points=");
  Serial.println(touch.getSupportTouchPoint());
  Serial.flush();
}

void handleTouch() {
  if (!touchReady || millis() - lastTouchMs < 600) {
    return;
  }
  uint8_t touched = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (touched == 0) {
    return;
  }
  lastTouchMs = millis();
  touchCount++;
  Serial.print("WEB_AI_TOUCH_EVENT count=");
  Serial.print(touchCount);
  Serial.print(" x=");
  Serial.print(touchX[0]);
  Serial.print(" y=");
  Serial.println(touchY[0]);
  Serial.flush();

  if (touchX[0] >= BUTTON_X && touchX[0] <= BUTTON_X + BUTTON_W && touchY[0] >= BUTTON_Y && touchY[0] <= BUTTON_Y + BUTTON_H) {
    if (WiFi.status() != WL_CONNECTED || aiEndpoint.length() == 0) {
      Serial.println("WEB_AI_TOUCH_IGNORED reason=not_ready");
      Serial.flush();
      drawScreen("Config needed", RGB565_YELLOW);
      return;
    }
    triggerAi("touch", "touch button");
  }
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("web_ai_button boot");
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  if (gfx->begin()) {
    gfx->setRotation(DISPLAY_ROTATION);
    gfx->setBrightness(DISPLAY_BRIGHTNESS);
    displayReady = true;
  } else {
    Serial.println("WEB_AI_DISPLAY_FAILED");
    Serial.flush();
  }

  setupTouch();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false, true);
  drawScreen("Config needed", RGB565_YELLOW);
  Serial.print((displayReady && touchReady) ? "WEB_AI_READY" : "WEB_AI_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.println(" wifi=0");
  Serial.flush();
}

void loop() {
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      handleCommand(inputLine);
      inputLine = "";
    } else if (c != '\r') {
      inputLine += c;
      if (inputLine.length() > 320) {
        inputLine = inputLine.substring(inputLine.length() - 320);
      }
    }
  }

  handleTouch();
  if ((frame % 200) == 0) {
    emitState();
  }
  frame++;
  delay(50);
}
