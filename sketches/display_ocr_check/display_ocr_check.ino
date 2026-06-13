#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include "pin_config.h"

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

uint32_t frame = 0;
bool displayReady = false;

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

void drawOcrScreen() {
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, RGB565_WHITE);
  gfx->drawRect(14, 14, LCD_WIDTH - 28, LCD_HEIGHT - 28, RGB565_BLUE);

  centerText("OK", 112, 10, RGB565_WHITE);
  centerText("2026", 246, 6, RGB565_YELLOW);
  centerText("ESP32 S3 AMOLED", 362, 2, RGB565_CYAN);
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("display_ocr_check boot");
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);

  if (!gfx->begin()) {
    Serial.println("display_ocr_check gfx begin failed");
    Serial.flush();
    return;
  }

  gfx->setBrightness(220);
  gfx->setRotation(DISPLAY_ROTATION);
  drawOcrScreen();
  displayReady = true;

  Serial.println("display_ocr_check text=OK 2026");
  Serial.flush();
}

void loop() {
  Serial.print("display_ocr_check frame=");
  Serial.print(frame++);
  Serial.print(" display=");
  Serial.println(displayReady ? "ready" : "failed");
  Serial.flush();
  delay(1000);
}
