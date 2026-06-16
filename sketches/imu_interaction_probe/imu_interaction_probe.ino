#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <SensorQMI8658.hpp>
#include <Wire.h>
#include <math.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

SensorQMI8658 qmi;

struct ImuSample {
  float ax;
  float ay;
  float az;
  float gx;
  float gy;
  float gz;
};

bool displayReady = false;
bool imuReady = false;
bool liveMode = true;
bool awake = true;
uint32_t frame = 0;
uint32_t eventCount = 0;
uint32_t injectedCount = 0;
uint32_t stepCount = 0;
uint32_t shakeCount = 0;
uint32_t wristWakeCount = 0;
uint32_t menuChanges = 0;
uint8_t pageIndex = 0;
String serialBuffer;
String currentPose = "REST";
String lastEvent = "BOOT";
ImuSample sample = {0, 0, 1, 0, 0, 0};

const char *pages[] = {"HOME", "STEPS", "POSE", "AGENT"};
const uint8_t pageCount = sizeof(pages) / sizeof(pages[0]);

float magnitude3(float x, float y, float z) {
  return sqrtf(x * x + y * y + z * z);
}

float accMagnitude(const ImuSample &item) {
  return magnitude3(item.ax, item.ay, item.az);
}

float gyroMagnitude(const ImuSample &item) {
  return magnitude3(item.gx, item.gy, item.gz);
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

String detectPose(const ImuSample &item) {
  if (item.az > 0.70f) {
    return "FACE_UP";
  }
  if (item.az < -0.70f) {
    return "FACE_DOWN";
  }
  if (item.ax < -0.60f) {
    return "TILT_LEFT";
  }
  if (item.ax > 0.60f) {
    return "TILT_RIGHT";
  }
  if (item.ay > 0.65f) {
    return "WRIST_UP";
  }
  if (item.ay < -0.65f) {
    return "WRIST_DOWN";
  }
  return "REST";
}

void drawInteractionScreen() {
  if (!displayReady) {
    return;
  }

  uint16_t border = awake ? RGB565_GREEN : RGB565_DARKGREY;
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, border);
  centerText("STEP", 42, 6, RGB565_CYAN);
  centerText(awake ? "OK" : "DIM", 126, 8, RGB565_WHITE);

  gfx->setTextSize(3);
  gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  gfx->setCursor(50, 244);
  gfx->print("PAGE ");
  gfx->print(pages[pageIndex]);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_GREEN, RGB565_BLACK);
  gfx->setCursor(50, 306);
  gfx->print("pose ");
  gfx->print(currentPose);

  gfx->setCursor(50, 342);
  gfx->print("steps ");
  gfx->print(stepCount);

  gfx->setCursor(50, 378);
  gfx->print("event ");
  gfx->print(lastEvent);
}

void emitEvent(const char *name, const char *source) {
  eventCount++;
  lastEvent = name;
  Serial.print("IMU_EVENT name=");
  Serial.print(name);
  Serial.print(" source=");
  Serial.print(source);
  Serial.print(" page=");
  Serial.print(pages[pageIndex]);
  Serial.print(" pose=");
  Serial.print(currentPose);
  Serial.print(" steps=");
  Serial.print(stepCount);
  Serial.print(" awake=");
  Serial.print(awake ? 1 : 0);
  Serial.print(" event_count=");
  Serial.println(eventCount);
  Serial.flush();
}

void emitStatus() {
  Serial.print("IMU_INTERACTION_STATUS frame=");
  Serial.print(frame);
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" imu=");
  Serial.print(imuReady ? 1 : 0);
  Serial.print(" live=");
  Serial.print(liveMode ? 1 : 0);
  Serial.print(" awake=");
  Serial.print(awake ? 1 : 0);
  Serial.print(" page=");
  Serial.print(pages[pageIndex]);
  Serial.print(" pose=");
  Serial.print(currentPose);
  Serial.print(" steps=");
  Serial.print(stepCount);
  Serial.print(" shakes=");
  Serial.print(shakeCount);
  Serial.print(" wrist_wakes=");
  Serial.print(wristWakeCount);
  Serial.print(" menu_changes=");
  Serial.print(menuChanges);
  Serial.print(" injected=");
  Serial.print(injectedCount);
  Serial.print(" event_count=");
  Serial.println(eventCount);
  Serial.flush();
}

void nextPage(const char *source) {
  pageIndex = (pageIndex + 1) % pageCount;
  menuChanges++;
  emitEvent("MENU_NEXT", source);
}

void runInteraction(const ImuSample &item, const char *source) {
  sample = item;
  currentPose = detectPose(item);
  float amag = accMagnitude(item);
  float gmag = gyroMagnitude(item);

  bool didEmit = false;
  if (!awake && currentPose == "WRIST_UP") {
    awake = true;
    wristWakeCount++;
    emitEvent("WRIST_WAKE", source);
    didEmit = true;
  }
  if (gmag > 150.0f || fabsf(amag - 1.0f) > 0.75f) {
    shakeCount++;
    nextPage(source);
    emitEvent("SHAKE_SWITCH", source);
    didEmit = true;
  }
  if (item.az > 1.25f && fabsf(item.gx) < 80.0f && fabsf(item.gy) < 80.0f) {
    stepCount++;
    emitEvent("STEP", source);
    didEmit = true;
  }
  if (currentPose == "TILT_LEFT" || currentPose == "TILT_RIGHT" || currentPose == "FACE_DOWN" || currentPose == "FACE_UP") {
    emitEvent("POSE_MENU", source);
    didEmit = true;
  }

  if (!didEmit) {
    lastEvent = "SAMPLE";
  }
  drawInteractionScreen();
}

bool parseSamplePayload(const String &payload, ImuSample &out) {
  float values[6] = {0, 0, 0, 0, 0, 0};
  int start = 0;
  for (int i = 0; i < 6; i++) {
    int end = payload.indexOf(',', start);
    String token = end >= 0 ? payload.substring(start, end) : payload.substring(start);
    token.trim();
    if (token.length() == 0) {
      return false;
    }
    values[i] = token.toFloat();
    start = end + 1;
    if (end < 0 && i < 5) {
      return false;
    }
  }
  out = {values[0], values[1], values[2], values[3], values[4], values[5]};
  return true;
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("IMU_INTERACTION_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(200);
  displayReady = true;
  drawInteractionScreen();
}

void setupImu() {
  imuReady = qmi.begin(Wire, QMI8658_L_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!imuReady) {
    Serial.println("IMU_INTERACTION_IMU_FAILED");
    Serial.flush();
    return;
  }

  qmi.configAccelerometer(
    SensorQMI8658::ACC_RANGE_4G,
    SensorQMI8658::ACC_ODR_125Hz,
    SensorQMI8658::LPF_MODE_0);
  qmi.configGyroscope(
    SensorQMI8658::GYR_RANGE_256DPS,
    SensorQMI8658::GYR_ODR_112_1Hz,
    SensorQMI8658::LPF_MODE_0);
  qmi.enableAccelerometer();
  qmi.enableGyroscope();
  Serial.println("IMU_INTERACTION_IMU_READY");
  Serial.flush();
}

void updateLiveSample() {
  if (!imuReady || !liveMode || !qmi.getDataReady()) {
    return;
  }

  IMUdata acc = {0, 0, 0};
  IMUdata gyr = {0, 0, 0};
  qmi.getAccelerometer(acc.x, acc.y, acc.z);
  qmi.getGyroscope(gyr.x, gyr.y, gyr.z);
  sample = {acc.x, acc.y, acc.z, gyr.x, gyr.y, gyr.z};
}

void handleCommand(String command) {
  command.trim();
  command.toUpperCase();
  if (command.length() == 0) {
    return;
  }
  if (command == "PING") {
    Serial.println("PONG");
    Serial.flush();
    return;
  }
  if (command == "STATUS?") {
    emitStatus();
    return;
  }
  if (command == "LIVE:1") {
    liveMode = true;
    Serial.println("IMU_INTERACTION_LIVE enabled=1");
    Serial.flush();
    return;
  }
  if (command == "LIVE:0") {
    liveMode = false;
    Serial.println("IMU_INTERACTION_LIVE enabled=0");
    Serial.flush();
    return;
  }
  if (command == "SLEEP") {
    awake = false;
    emitEvent("SLEEP", "serial");
    drawInteractionScreen();
    return;
  }
  if (command == "WAKE") {
    awake = true;
    emitEvent("WAKE", "serial");
    drawInteractionScreen();
    return;
  }
  if (command == "MENU:NEXT") {
    nextPage("serial");
    drawInteractionScreen();
    return;
  }
  if (command == "RESET") {
    stepCount = 0;
    shakeCount = 0;
    wristWakeCount = 0;
    menuChanges = 0;
    eventCount = 0;
    pageIndex = 0;
    awake = true;
    lastEvent = "RESET";
    currentPose = "REST";
    Serial.println("IMU_INTERACTION_RESET ok=1");
    Serial.flush();
    drawInteractionScreen();
    return;
  }
  if (command.startsWith("SAMPLE:")) {
    ImuSample injected;
    if (!parseSamplePayload(command.substring(7), injected)) {
      Serial.print("IMU_INTERACTION_BAD_SAMPLE value=");
      Serial.println(command.substring(7));
      Serial.flush();
      return;
    }
    liveMode = false;
    injectedCount++;
    runInteraction(injected, "serial");
    return;
  }

  Serial.print("IMU_INTERACTION_UNKNOWN_COMMAND value=");
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
      Serial.println("IMU_INTERACTION_COMMAND_TOO_LONG");
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

  Serial.println("imu_interaction_probe boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupImu();
  Serial.print((displayReady && imuReady) ? "IMU_INTERACTION_READY" : "IMU_INTERACTION_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" imu=");
  Serial.println(imuReady ? 1 : 0);
  Serial.flush();
  emitStatus();
}

void loop() {
  readSerialCommands();
  updateLiveSample();

  if (liveMode && (frame % 10) == 0) {
    runInteraction(sample, "live");
  }
  if ((frame % 40) == 0) {
    emitStatus();
  }

  frame++;
  delay(50);
}
