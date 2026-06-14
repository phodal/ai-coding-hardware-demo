#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

uint32_t frame = 0;
bool displayReady = false;

void drawStatusScreen() {
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRoundRect(18, 18, 430, 430, 24, RGB565_BLUE);

  gfx->setTextColor(RGB565_CYAN);
  gfx->setTextSize(6);
  gfx->setCursor(36, 96);
  gfx->println("Qoder");

  gfx->setTextColor(RGB565_GREEN);
  gfx->setTextSize(5);
  gfx->setCursor(152, 220);
  gfx->println("OK");

  gfx->setTextColor(RGB565_YELLOW);
  gfx->setTextSize(2);
  gfx->setCursor(78, 316);
  gfx->println("ESP32-S3 AMOLED");

  gfx->setTextColor(RGB565_WHITE);
  gfx->setTextSize(1);
  gfx->setCursor(112, 360);
  gfx->println("Build/upload automation");
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("codex_hello_world boot");
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);

  if (!gfx->begin()) {
    Serial.println("gfx->begin() failed");
    return;
  }

  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(160);
  drawStatusScreen();
  displayReady = true;
  Serial.println("codex_hello_world display ready");
  Serial.flush();
}

void loop() {
  if (displayReady) {
    gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
    gfx->setTextSize(2);
    gfx->setCursor(156, 396);
    gfx->print("frame ");
    gfx->print(frame);
    gfx->print("     ");
  }

  Serial.print("codex_hello_world frame=");
  Serial.println(frame);
  Serial.flush();

  frame++;
  delay(500);
}
