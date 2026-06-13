#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

TouchDrvCST92xx touch;

enum WidgetPage {
  WIDGET_HOME = 0,
  WIDGET_STATUS,
  WIDGET_TIMER,
  WIDGET_SUMMARY,
};

bool displayReady = false;
bool touchReady = false;
uint32_t frame = 0;
uint32_t touchEvents = 0;
uint32_t alertCount = 0;
uint32_t githubCount = 0;
uint32_t timerSeconds = 25 * 60;
uint32_t lastTimerTickMs = 0;
bool timerRunning = false;
WidgetPage currentPage = WIDGET_HOME;
String serialBuffer;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};
char ciState[16] = "OK";
char ciLabel[32] = "CI PASS";
char summary[96] = "Ready for AI notes";
char alertText[64] = "No alerts";

const char *pageName(WidgetPage page) {
  switch (page) {
    case WIDGET_HOME:
      return "HOME";
    case WIDGET_STATUS:
      return "STATUS";
    case WIDGET_TIMER:
      return "TIMER";
    case WIDGET_SUMMARY:
      return "SUMMARY";
  }
  return "HOME";
}

bool parsePage(const String &name, WidgetPage &page) {
  if (name == "HOME" || name == "WIDGET") {
    page = WIDGET_HOME;
    return true;
  }
  if (name == "STATUS" || name == "CI") {
    page = WIDGET_STATUS;
    return true;
  }
  if (name == "TIMER" || name == "POMODORO") {
    page = WIDGET_TIMER;
    return true;
  }
  if (name == "SUMMARY" || name == "AI") {
    page = WIDGET_SUMMARY;
    return true;
  }
  return false;
}

uint16_t statusColor() {
  if (strcmp(ciState, "FAIL") == 0) {
    return RGB565_RED;
  }
  if (strcmp(ciState, "WARN") == 0) {
    return RGB565_YELLOW;
  }
  return RGB565_GREEN;
}

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

void drawLabel(const char *label, int16_t y, uint16_t color) {
  gfx->setTextSize(2);
  gfx->setTextColor(color, RGB565_BLACK);
  gfx->setCursor(44, y);
  gfx->print(label);
}

void drawWrapped(const char *text, int16_t x, int16_t y, int16_t maxChars, uint16_t color) {
  gfx->setTextSize(2);
  gfx->setTextColor(color, RGB565_BLACK);
  int16_t lineY = y;
  int16_t count = 0;
  gfx->setCursor(x, lineY);
  for (const char *cursor = text; *cursor != '\0'; cursor++) {
    if (*cursor == '\n' || count >= maxChars) {
      lineY += 28;
      count = 0;
      gfx->setCursor(x, lineY);
      if (*cursor == '\n') {
        continue;
      }
    }
    gfx->print(*cursor);
    count++;
  }
}

void drawFrame(uint16_t color) {
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, color);
}

void drawTimerValue() {
  char timeText[8];
  uint32_t minutes = timerSeconds / 60;
  uint32_t seconds = timerSeconds % 60;
  snprintf(timeText, sizeof(timeText), "%02lu:%02lu", minutes, seconds);
  centerText(timeText, 132, 7, RGB565_WHITE);
}

void drawPage() {
  if (!displayReady) {
    return;
  }

  switch (currentPage) {
    case WIDGET_HOME:
      drawFrame(statusColor());
      centerText("WIDG", 44, 6, RGB565_CYAN);
      centerText("OK", 132, 9, RGB565_WHITE);
      drawLabel(ciLabel, 292, statusColor());
      drawLabel("alerts=", 330, RGB565_GREEN);
      gfx->print(alertCount);
      drawLabel("github=", 368, RGB565_GREEN);
      gfx->print(githubCount);
      break;
    case WIDGET_STATUS:
      drawFrame(statusColor());
      centerText("STATUS", 44, 5, RGB565_CYAN);
      centerText(ciState, 132, 8, statusColor());
      drawLabel(ciLabel, 292, RGB565_WHITE);
      drawLabel(alertText, 330, RGB565_YELLOW);
      break;
    case WIDGET_TIMER:
      drawFrame(timerRunning ? RGB565_GREEN : RGB565_YELLOW);
      centerText("TIMER", 44, 6, RGB565_CYAN);
      drawTimerValue();
      centerText(timerRunning ? "RUN" : "PAUSE", 270, 4, timerRunning ? RGB565_GREEN : RGB565_YELLOW);
      break;
    case WIDGET_SUMMARY:
      drawFrame(RGB565_CYAN);
      centerText("AI NOTE", 44, 5, RGB565_CYAN);
      drawWrapped(summary, 44, 150, 24, RGB565_WHITE);
      break;
  }
}

void emitPage(const char *source) {
  Serial.print("WIDGET_PAGE page=");
  Serial.print(pageName(currentPage));
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void emitState() {
  Serial.print("WIDGET_STATE frame=");
  Serial.print(frame);
  Serial.print(" page=");
  Serial.print(pageName(currentPage));
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" ci=");
  Serial.print(ciState);
  Serial.print(" github=");
  Serial.print(githubCount);
  Serial.print(" alerts=");
  Serial.print(alertCount);
  Serial.print(" timer=");
  Serial.print(timerSeconds);
  Serial.print(" running=");
  Serial.print(timerRunning ? 1 : 0);
  Serial.print(" summary_len=");
  Serial.println(strlen(summary));
  Serial.flush();
}

void setPage(WidgetPage page, const char *source) {
  currentPage = page;
  drawPage();
  emitPage(source);
}

void copyString(char *target, size_t targetSize, const String &value) {
  String sanitized = value;
  sanitized.replace("\r", " ");
  sanitized.replace("\n", " ");
  sanitized.trim();
  strlcpy(target, sanitized.c_str(), targetSize);
}

void setCiState(const String &state, const String &label) {
  if (state == "FAIL" || state == "RED") {
    strlcpy(ciState, "FAIL", sizeof(ciState));
  } else if (state == "WARN" || state == "YELLOW") {
    strlcpy(ciState, "WARN", sizeof(ciState));
  } else {
    strlcpy(ciState, "OK", sizeof(ciState));
  }

  if (label.length() > 0) {
    copyString(ciLabel, sizeof(ciLabel), label);
  } else if (strcmp(ciState, "FAIL") == 0) {
    strlcpy(ciLabel, "CI FAIL", sizeof(ciLabel));
  } else if (strcmp(ciState, "WARN") == 0) {
    strlcpy(ciLabel, "CI WARN", sizeof(ciLabel));
  } else {
    strlcpy(ciLabel, "CI PASS", sizeof(ciLabel));
  }

  setPage(WIDGET_STATUS, "serial");
}

void updateTimer() {
  if (!timerRunning || timerSeconds == 0) {
    lastTimerTickMs = millis();
    return;
  }

  uint32_t now = millis();
  if (now - lastTimerTickMs >= 1000) {
    uint32_t elapsed = (now - lastTimerTickMs) / 1000;
    lastTimerTickMs += elapsed * 1000;
    timerSeconds = (elapsed >= timerSeconds) ? 0 : timerSeconds - elapsed;
    if (timerSeconds == 0) {
      timerRunning = false;
      alertCount++;
      strlcpy(alertText, "Timer done", sizeof(alertText));
      Serial.println("WIDGET_TIMER_DONE");
      Serial.flush();
    }
    if (currentPage == WIDGET_TIMER) {
      drawPage();
    }
  }
}

void resetTouchPins() {
  pinMode(TP_RST, OUTPUT);
  digitalWrite(TP_RST, LOW);
  delay(30);
  digitalWrite(TP_RST, HIGH);
  delay(150);
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("WIDGET_DISPLAY_FAILED");
    Serial.flush();
    return;
  }

  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(190);
  displayReady = true;
  drawPage();
}

void setupTouch() {
  resetTouchPins();
  touch.setPins(TP_RST, TP_INT);
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!touchReady) {
    Serial.println("WIDGET_TOUCH_FAILED");
    Serial.flush();
    return;
  }

  touch.reset();
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setMirrorXY(true, true);
  Serial.print("WIDGET_TOUCH_READY model=");
  Serial.print(touch.getModelName());
  Serial.print(" points=");
  Serial.println(touch.getSupportTouchPoint());
  Serial.flush();
}

void handleTouch() {
  if (!touchReady) {
    return;
  }

  uint8_t touched = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (touched == 0) {
    return;
  }

  touchEvents++;
  Serial.print("WIDGET_TOUCH_EVENT count=");
  Serial.print(touchEvents);
  Serial.print(" x=");
  Serial.print(touchX[0]);
  Serial.print(" y=");
  Serial.println(touchY[0]);
  Serial.flush();
  setPage(static_cast<WidgetPage>((currentPage + 1) % 4), "touch");
  delay(220);
}

void handleCommand(String command) {
  command.trim();
  if (command.length() == 0) {
    return;
  }

  String upper = command;
  upper.toUpperCase();
  if (upper == "PING") {
    Serial.println("PONG");
    Serial.flush();
    return;
  }
  if (upper == "STATE?") {
    emitState();
    return;
  }
  if (upper == "NEXT") {
    setPage(static_cast<WidgetPage>((currentPage + 1) % 4), "serial");
    return;
  }
  if (upper.startsWith("PAGE:")) {
    WidgetPage page;
    if (parsePage(upper.substring(5), page)) {
      setPage(page, "serial");
    } else {
      Serial.print("WIDGET_BAD_PAGE value=");
      Serial.println(upper.substring(5));
      Serial.flush();
    }
    return;
  }
  if (upper.startsWith("WIDGET:CI:")) {
    int labelIndex = command.indexOf(':', 10);
    if (labelIndex > 0) {
      setCiState(upper.substring(10, labelIndex), command.substring(labelIndex + 1));
    } else {
      setCiState(upper.substring(10), "");
    }
    return;
  }
  if (upper.startsWith("WIDGET:GITHUB:")) {
    githubCount = static_cast<uint32_t>(max(0L, command.substring(14).toInt()));
    setPage(WIDGET_STATUS, "serial");
    return;
  }
  if (upper.startsWith("WIDGET:ALERT:")) {
    alertCount++;
    copyString(alertText, sizeof(alertText), command.substring(13));
    Serial.print("WIDGET_ALERT count=");
    Serial.print(alertCount);
    Serial.print(" text=");
    Serial.println(alertText);
    Serial.flush();
    setPage(WIDGET_STATUS, "serial");
    return;
  }
  if (upper.startsWith("WIDGET:SUMMARY:")) {
    copyString(summary, sizeof(summary), command.substring(15));
    setPage(WIDGET_SUMMARY, "serial");
    return;
  }
  if (upper.startsWith("TIMER:SET:")) {
    uint32_t minutes = static_cast<uint32_t>(max(0L, command.substring(10).toInt()));
    timerSeconds = min<uint32_t>(minutes * 60, 99 * 60 + 59);
    timerRunning = false;
    setPage(WIDGET_TIMER, "serial");
    return;
  }
  if (upper == "TIMER:START") {
    timerRunning = true;
    lastTimerTickMs = millis();
    setPage(WIDGET_TIMER, "serial");
    return;
  }
  if (upper == "TIMER:PAUSE") {
    timerRunning = false;
    setPage(WIDGET_TIMER, "serial");
    return;
  }
  if (upper == "TIMER:RESET") {
    timerSeconds = 25 * 60;
    timerRunning = false;
    setPage(WIDGET_TIMER, "serial");
    return;
  }

  Serial.print("WIDGET_UNKNOWN_COMMAND value=");
  Serial.println(command);
  Serial.flush();
}

void readSerialCommands() {
  while (Serial.available() > 0) {
    char ch = static_cast<char>(Serial.read());
    if (ch == '\r') {
      continue;
    }
    if (ch == '\n') {
      handleCommand(serialBuffer);
      serialBuffer = "";
      continue;
    }
    if (serialBuffer.length() < 140) {
      serialBuffer += ch;
    } else {
      serialBuffer = "";
      Serial.println("WIDGET_COMMAND_TOO_LONG");
      Serial.flush();
    }
  }
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("desk_widget boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();

  Serial.print((displayReady && touchReady) ? "WIDGET_READY" : "WIDGET_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.println(touchReady ? 1 : 0);
  Serial.flush();
  emitPage("boot");
  emitState();
}

void loop() {
  readSerialCommands();
  updateTimer();
  handleTouch();

  if ((frame % 20) == 0) {
    emitState();
    drawPage();
  }

  frame++;
  delay(50);
}
