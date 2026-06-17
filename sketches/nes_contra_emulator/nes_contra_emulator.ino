#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
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

bool displayReady = false;
bool touchReady = false;
uint32_t frame = 0;
uint32_t inputEvents = 0;
uint32_t touchEvents = 0;
uint32_t lastFrameDraw = 0;
String serialBuffer;
char lastButtons[40] = "none";
int16_t lastRunnerX = -1;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};

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

void drawStaticScreen() {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRoundRect(18, 18, 430, 430, 18, RGB565_RED);
  gfx->drawRoundRect(28, 28, 410, 410, 16, RGB565_BLUE);
  centerText("NES", 58, 6, RGB565_CYAN);
  centerText("CONTRA", 132, 5, RGB565_GREEN);
  centerText("OK", 224, 8, RGB565_WHITE);
  gfx->drawRect(58, 308, 350, 34, RGB565_BLUE);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  gfx->setCursor(58, 352);
  gfx->print("mapper=2 rom=missing");
  gfx->setCursor(58, 378);
  gfx->print("mode=diagnostic");
}

void drawRunnerAnimation() {
  const int16_t trackX = 58;
  const int16_t trackY = 308;
  const int16_t trackW = 350;
  const int16_t runnerW = 30;
  const int16_t travel = trackW - runnerW - 4;
  const int16_t phase = (frame * 7) % (travel * 2);
  const int16_t runnerX = trackX + 2 + (phase < travel ? phase : (travel * 2 - phase));
  const int16_t runnerY = trackY + 10;

  if (lastRunnerX >= 0) {
    gfx->fillRect(lastRunnerX - 3, trackY + 1, runnerW + 8, 32, RGB565_BLACK);
  }

  gfx->drawRect(trackX, trackY, trackW, 34, RGB565_BLUE);
  gfx->fillRect(runnerX, runnerY, runnerW, 9, RGB565_GREEN);
  gfx->fillRect(runnerX + 5, runnerY - 6, 11, 6, RGB565_CYAN);
  gfx->fillRect(runnerX + 19, runnerY + 9, 7, 6, RGB565_YELLOW);
  gfx->fillRect(runnerX + (((frame / 5) % 2) == 0 ? 3 : 15), runnerY + 9, 7, 6, RGB565_RED);
  lastRunnerX = runnerX;
}

void drawDynamicStatus() {
  if (!displayReady || millis() - lastFrameDraw < 100) {
    return;
  }
  lastFrameDraw = millis();
  drawRunnerAnimation();
  gfx->fillRect(54, 404, 360, 28, RGB565_BLACK);
  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_WHITE, RGB565_BLACK);
  gfx->setCursor(58, 408);
  gfx->print("frame=");
  gfx->print(frame);
  gfx->print(" input=");
  gfx->print(lastButtons);
}

void emitReady() {
  Serial.print("NES_CONTRA_READY display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" mode=diagnostic target_mapper=2 rom=missing frames=");
  Serial.println(frame);
  Serial.flush();
}

void emitState(const char *kind) {
  Serial.print(kind);
  Serial.print(" frame=");
  Serial.print(frame);
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" mode=diagnostic target_mapper=2 rom=missing buttons=");
  Serial.print(lastButtons);
  Serial.print(" input_events=");
  Serial.print(inputEvents);
  Serial.print(" touch_events=");
  Serial.println(touchEvents);
  Serial.flush();
}

void setButtons(const String &buttons) {
  String sanitized = buttons;
  sanitized.trim();
  sanitized.replace(" ", "_");
  sanitized.replace("\r", "");
  sanitized.replace("\n", "");
  if (sanitized.length() == 0) {
    sanitized = "none";
  }
  sanitized.toCharArray(lastButtons, sizeof(lastButtons));
  inputEvents++;
  Serial.print("NES_CONTRA_INPUT buttons=");
  Serial.print(lastButtons);
  Serial.print(" events=");
  Serial.println(inputEvents);
  Serial.flush();
}

void handleCommand(String command) {
  command.trim();
  if (command.length() == 0) {
    return;
  }
  if (command == "PING") {
    Serial.println("PONG");
  } else if (command == "CAPS?") {
    Serial.println("NES_CONTRA_CAPS display=co5300 size=466x466 input=serial,touch target_mapper=2 audio=pending");
  } else if (command == "ROM?") {
    Serial.println("NES_CONTRA_ROM status=missing target_mapper=2 source=generated-header-required");
  } else if (command == "FRAME?") {
    emitState("NES_CONTRA_FRAME");
  } else if (command == "STATE?") {
    emitState("NES_CONTRA_STATE");
  } else if (command.startsWith("INPUT:")) {
    setButtons(command.substring(6));
  } else if (command == "READY?") {
    emitReady();
  } else {
    Serial.print("NES_CONTRA_UNKNOWN command=");
    Serial.println(command);
  }
  Serial.flush();
}

void pollSerial() {
  while (Serial.available() > 0) {
    char ch = static_cast<char>(Serial.read());
    if (ch == '\n' || ch == '\r') {
      handleCommand(serialBuffer);
      serialBuffer = "";
    } else if (serialBuffer.length() < 96) {
      serialBuffer += ch;
    }
  }
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("NES_CONTRA_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(DISPLAY_BRIGHTNESS);
  displayReady = true;
  drawStaticScreen();
}

void setupTouch() {
  touch.setPins(TP_RST, TP_INT);
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (touchReady) {
    touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
    touch.setSwapXY(true);
    touch.setMirrorXY(false, true);
  }
}

void pollTouch() {
  if (!touchReady || !touch.isPressed()) {
    return;
  }
  uint8_t points = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (points == 0) {
    return;
  }
  touchEvents++;
  strlcpy(lastButtons, "TOUCH", sizeof(lastButtons));
  Serial.print("NES_CONTRA_TOUCH points=");
  Serial.print(points);
  Serial.print(" x=");
  Serial.print(touchX[0]);
  Serial.print(" y=");
  Serial.print(touchY[0]);
  Serial.print(" events=");
  Serial.println(touchEvents);
  Serial.flush();
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("nes_contra_emulator boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();
  emitReady();
}

void loop() {
  pollSerial();
  pollTouch();
  drawDynamicStatus();

  if ((frame % 20) == 0) {
    emitState("NES_CONTRA_FRAME");
  }
  frame++;
  delay(50);
}
