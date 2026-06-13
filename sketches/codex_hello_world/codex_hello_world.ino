#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include "pin_config.h"

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

uint32_t frame = 0;
bool displayReady = false;

void drawStatusScreen() {
  gfx->fillScreen(RGB565_BLACK);
  gfx->setTextColor(RGB565_CYAN);
  gfx->setTextSize(2);
  gfx->setCursor(24, 40);
  gfx->println("Codex Arduino CLI");

  gfx->setTextColor(RGB565_GREEN);
  gfx->setTextSize(2);
  gfx->setCursor(24, 82);
  gfx->println("ESP32-S3 AMOLED");

  gfx->setTextColor(RGB565_YELLOW);
  gfx->setTextSize(1);
  gfx->setCursor(24, 128);
  gfx->println("Build/upload automation OK");

  gfx->drawRoundRect(20, 155, 426, 92, 12, RGB565_BLUE);
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

  gfx->setBrightness(160);
  drawStatusScreen();
  displayReady = true;
  Serial.println("codex_hello_world display ready");
  Serial.flush();
}

void loop() {
  const uint16_t colors[] = {
    RGB565_RED,
    RGB565_ORANGE,
    RGB565_YELLOW,
    RGB565_GREEN,
    RGB565_CYAN,
    RGB565_BLUE,
    RGB565_MAGENTA,
    RGB565_WHITE
  };

  if (displayReady) {
    uint16_t color = colors[frame % (sizeof(colors) / sizeof(colors[0]))];
    int x = 36 + ((frame * 29) % 350);
    int y = 180 + ((frame * 17) % 220);

    gfx->fillCircle(x, y, 14, color);
    gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
    gfx->setTextSize(2);
    gfx->setCursor(36, 268);
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
