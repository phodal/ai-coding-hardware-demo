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

bool displayReady = false;
bool touchReady = false;
uint32_t frame = 0;
uint32_t touchCount = 0;
int16_t xs[5] = {0};
int16_t ys[5] = {0};
char modelName[32] = "unknown";

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

void drawTouchScreen(const char *status, uint16_t color, int16_t x, int16_t y) {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, color);
  centerText("TOUCH", 48, 5, RGB565_CYAN);
  centerText(status, 136, 9, RGB565_WHITE);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  gfx->setCursor(50, 316);
  gfx->print(modelName);
  gfx->setCursor(50, 350);
  gfx->print("events=");
  gfx->print(touchCount);

  if (x >= 0 && y >= 0) {
    gfx->fillCircle(x, y, 16, RGB565_GREEN);
    gfx->setCursor(50, 384);
    gfx->print("x=");
    gfx->print(x);
    gfx->print(" y=");
    gfx->print(y);
  }
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("touch_status_probe gfx begin failed");
    Serial.flush();
    return;
  }

  gfx->setBrightness(200);
  gfx->setRotation(DISPLAY_ROTATION);
  displayReady = true;
  drawTouchScreen("WAIT", RGB565_BLUE, -1, -1);
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
    Serial.println("TOUCH_FAILED");
    Serial.flush();
    drawTouchScreen("FAIL", RGB565_RED, -1, -1);
    return;
  }

  const char *name = touch.getModelName();
  if (name != nullptr) {
    strlcpy(modelName, name, sizeof(modelName));
  }
  touch.reset();
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setMirrorXY(true, true);
  Serial.print("TOUCH_READY model=");
  Serial.print(modelName);
  Serial.print(" points=");
  Serial.println(touch.getSupportTouchPoint());
  Serial.flush();
  drawTouchScreen("OK", RGB565_GREEN, -1, -1);
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("touch_status_probe boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();
}

void loop() {
  uint8_t touched = 0;
  if (touchReady) {
    touched = touch.getPoint(xs, ys, touch.getSupportTouchPoint());
  }

  if (touched > 0) {
    touchCount++;
    Serial.print("TOUCH_EVENT count=");
    Serial.print(touchCount);
    Serial.print(" points=");
    Serial.print(touched);
    Serial.print(" x=");
    Serial.print(xs[0]);
    Serial.print(" y=");
    Serial.println(ys[0]);
    Serial.flush();
    drawTouchScreen("TAP", RGB565_GREEN, xs[0], ys[0]);
  }

  if ((frame % 20) == 0) {
    Serial.print("TOUCH_STATUS frame=");
    Serial.print(frame);
    Serial.print(" ready=");
    Serial.print(touchReady ? 1 : 0);
    Serial.print(" model=");
    Serial.print(modelName);
    Serial.print(" events=");
    Serial.print(touchCount);
    Serial.print(" int=");
    Serial.println(digitalRead(TP_INT));
    Serial.flush();
    if (touchCount == 0) {
      drawTouchScreen(touchReady ? "OK" : "FAIL", touchReady ? RGB565_GREEN : RGB565_RED, -1, -1);
    }
  }

  frame++;
  delay(50);
}
