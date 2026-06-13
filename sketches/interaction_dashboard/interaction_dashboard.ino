#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <SensorQMI8658.hpp>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
#include <math.h>
#include "pin_config.h"
#include <XPowersLib.h>

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

XPowersPMU power;
SensorQMI8658 qmi;
TouchDrvCST92xx touch;

enum DashboardPage {
  PAGE_HOME = 0,
  PAGE_IMU,
  PAGE_PWR,
  PAGE_TOUCH,
};

enum DashboardPowerMode {
  POWER_ACTIVE = 0,
  POWER_DIM,
  POWER_STANDBY,
};

bool displayReady = false;
bool pmuReady = false;
bool imuReady = false;
bool touchReady = false;
uint32_t frame = 0;
uint32_t touchEvents = 0;
uint32_t gestureEvents = 0;
uint32_t lastActivityMs = 0;
uint32_t idleDimMs = 30000;
uint32_t lastGestureMs = 0;
uint8_t activeBrightness = 200;
DashboardPage currentPage = PAGE_HOME;
DashboardPowerMode powerMode = POWER_ACTIVE;
String serialBuffer;
IMUdata acc = {0, 0, 0};
IMUdata gyr = {0, 0, 0};
float previousAccMagnitude = 0.0f;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};
char touchModel[32] = "unknown";
char lastGesture[16] = "NONE";

const char *pageName(DashboardPage page) {
  switch (page) {
    case PAGE_HOME:
      return "HOME";
    case PAGE_IMU:
      return "IMU";
    case PAGE_PWR:
      return "PWR";
    case PAGE_TOUCH:
      return "TOUCH";
  }
  return "HOME";
}

const char *powerModeName(DashboardPowerMode mode) {
  switch (mode) {
    case POWER_ACTIVE:
      return "ACTIVE";
    case POWER_DIM:
      return "DIM";
    case POWER_STANDBY:
      return "STANDBY";
  }
  return "ACTIVE";
}

bool parsePage(const String &name, DashboardPage &page) {
  if (name == "HOME" || name == "DASH") {
    page = PAGE_HOME;
    return true;
  }
  if (name == "IMU") {
    page = PAGE_IMU;
    return true;
  }
  if (name == "PWR" || name == "PMU" || name == "POWER") {
    page = PAGE_PWR;
    return true;
  }
  if (name == "TOUCH") {
    page = PAGE_TOUCH;
    return true;
  }
  return false;
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

void drawMetricLabel(const char *label, int16_t y, uint16_t color) {
  gfx->setTextSize(2);
  gfx->setTextColor(color, RGB565_BLACK);
  gfx->setCursor(54, y);
  gfx->print(label);
}

float accMagnitude() {
  return sqrtf(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z);
}

uint16_t systemMv() {
  return pmuReady ? power.getSystemVoltage() : 0;
}

uint16_t vbusMv() {
  return pmuReady ? power.getVbusVoltage() : 0;
}

uint16_t battMv() {
  return pmuReady ? power.getBattVoltage() : 0;
}

float maxAbsGyro() {
  return max(max(fabsf(gyr.x), fabsf(gyr.y)), fabsf(gyr.z));
}

void applyBrightness() {
  if (!displayReady) {
    return;
  }

  uint8_t brightness = activeBrightness;
  if (powerMode == POWER_DIM) {
    brightness = min<uint8_t>(activeBrightness, 28);
  } else if (powerMode == POWER_STANDBY) {
    brightness = 0;
  }
  gfx->setBrightness(brightness);
}

void emitPower(const char *source) {
  Serial.print("DASH_POWER mode=");
  Serial.print(powerModeName(powerMode));
  Serial.print(" brightness=");
  Serial.print(activeBrightness);
  Serial.print(" idle_ms=");
  Serial.print(idleDimMs);
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void setPowerMode(DashboardPowerMode mode, const char *source);
void drawPage();

void markActivity() {
  lastActivityMs = millis();
  if (powerMode == POWER_DIM) {
    setPowerMode(POWER_ACTIVE, "activity");
  }
}

void drawPage() {
  if (!displayReady) {
    return;
  }

  if (powerMode == POWER_STANDBY) {
    gfx->fillScreen(RGB565_BLACK);
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, RGB565_CYAN);

  switch (currentPage) {
    case PAGE_HOME:
      centerText("DASH", 44, 6, RGB565_YELLOW);
      centerText((pmuReady && imuReady && touchReady) ? "OK" : "WAIT", 132, 9, RGB565_WHITE);
      drawMetricLabel(powerModeName(powerMode), 286, RGB565_GREEN);
      drawMetricLabel("Serial: PAGE:IMU", 322, RGB565_GREEN);
      drawMetricLabel("Tap or shake", 358, RGB565_GREEN);
      break;
    case PAGE_IMU:
      centerText("IMU", 48, 6, RGB565_YELLOW);
      centerText(imuReady ? "OK" : "FAIL", 132, 9, RGB565_WHITE);
      drawMetricLabel("ACC ", 292, RGB565_GREEN);
      gfx->print(accMagnitude(), 2);
      gfx->print("g");
      drawMetricLabel("GYR ", 330, RGB565_GREEN);
      gfx->print(gyr.x, 1);
      gfx->print(",");
      gfx->print(gyr.y, 1);
      drawMetricLabel("GEST ", 368, RGB565_GREEN);
      gfx->print(lastGesture);
      break;
    case PAGE_PWR:
      centerText("PWR", 48, 6, RGB565_YELLOW);
      centerText(pmuReady ? "OK" : "FAIL", 132, 9, RGB565_WHITE);
      drawMetricLabel("SYS ", 292, RGB565_GREEN);
      gfx->print(systemMv());
      gfx->print("mV");
      drawMetricLabel("VBUS ", 330, RGB565_GREEN);
      gfx->print(vbusMv());
      gfx->print("mV");
      drawMetricLabel("BATT ", 368, RGB565_GREEN);
      gfx->print(battMv());
      gfx->print("mV");
      drawMetricLabel("BRI ", 406, RGB565_GREEN);
      gfx->print(activeBrightness);
      break;
    case PAGE_TOUCH:
      centerText("TOUCH", 48, 5, RGB565_YELLOW);
      centerText(touchReady ? "OK" : "FAIL", 132, 9, RGB565_WHITE);
      drawMetricLabel(touchModel, 300, RGB565_GREEN);
      drawMetricLabel("events=", 336, RGB565_GREEN);
      gfx->print(touchEvents);
      drawMetricLabel("gestures=", 374, RGB565_GREEN);
      gfx->print(gestureEvents);
      break;
  }
}

void setPowerMode(DashboardPowerMode mode, const char *source) {
  powerMode = mode;
  if (mode == POWER_ACTIVE) {
    lastActivityMs = millis();
  }
  applyBrightness();
  drawPage();
  emitPower(source);
}

void emitPage(const char *source) {
  Serial.print("DASH_PAGE page=");
  Serial.print(pageName(currentPage));
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void setPage(DashboardPage page, const char *source) {
  markActivity();
  currentPage = page;
  drawPage();
  emitPage(source);
}

void emitGesture(const char *type, const char *source) {
  strlcpy(lastGesture, type, sizeof(lastGesture));
  gestureEvents++;
  Serial.print("DASH_GESTURE type=");
  Serial.print(type);
  Serial.print(" source=");
  Serial.print(source);
  Serial.print(" count=");
  Serial.print(gestureEvents);
  Serial.print(" amag=");
  Serial.print(accMagnitude(), 3);
  Serial.print(" gyro=");
  Serial.print(maxAbsGyro(), 3);
  Serial.print(" page=");
  Serial.println(pageName(currentPage));
  Serial.flush();
}

void handleGesture(const char *type, const char *source) {
  markActivity();
  emitGesture(type, source);
  if (strcmp(type, "SHAKE") == 0) {
    setPage(PAGE_IMU, source);
  } else if (strcmp(type, "TILT_LEFT") == 0) {
    setPage(static_cast<DashboardPage>((currentPage + 3) % 4), source);
  } else if (strcmp(type, "TILT_RIGHT") == 0) {
    setPage(static_cast<DashboardPage>((currentPage + 1) % 4), source);
  } else {
    drawPage();
  }
}

void emitStatus() {
  Serial.print("DASH_STATUS frame=");
  Serial.print(frame);
  Serial.print(" page=");
  Serial.print(pageName(currentPage));
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" pmu=");
  Serial.print(pmuReady ? 1 : 0);
  Serial.print(" imu=");
  Serial.print(imuReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" events=");
  Serial.print(touchEvents);
  Serial.print(" system_mv=");
  Serial.print(systemMv());
  Serial.print(" vbus_mv=");
  Serial.print(vbusMv());
  Serial.print(" batt_mv=");
  Serial.print(battMv());
  Serial.print(" amag=");
  Serial.print(accMagnitude(), 3);
  Serial.print(" gx=");
  Serial.print(gyr.x, 3);
  Serial.print(" gy=");
  Serial.print(gyr.y, 3);
  Serial.print(" gz=");
  Serial.print(gyr.z, 3);
  Serial.print(" power=");
  Serial.print(powerModeName(powerMode));
  Serial.print(" brightness=");
  Serial.print(activeBrightness);
  Serial.print(" gestures=");
  Serial.print(gestureEvents);
  Serial.print(" last_gesture=");
  Serial.print(lastGesture);
  Serial.print(" idle_ms=");
  Serial.println(idleDimMs);
  Serial.flush();
}

void enablePmuAdc() {
  power.enableTemperatureMeasure();
  power.enableBattDetection();
  power.enableVbusVoltageMeasure();
  power.enableBattVoltageMeasure();
  power.enableSystemVoltageMeasure();
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("DASH_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  displayReady = true;
  applyBrightness();
  drawPage();
}

void setupPmu() {
  pmuReady = power.begin(Wire, AXP2101_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!pmuReady) {
    Serial.println("DASH_PMU_FAILED");
    Serial.flush();
    return;
  }
  power.disableIRQ(XPOWERS_AXP2101_ALL_IRQ);
  power.clearIrqStatus();
  power.setChargeTargetVoltage(3);
  enablePmuAdc();
  Serial.println("DASH_PMU_READY");
  Serial.flush();
}

void setupImu() {
  imuReady = qmi.begin(Wire, QMI8658_L_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!imuReady) {
    Serial.println("DASH_IMU_FAILED");
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
  Serial.println("DASH_IMU_READY");
  Serial.flush();
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
    Serial.println("DASH_TOUCH_FAILED");
    Serial.flush();
    return;
  }

  const char *name = touch.getModelName();
  if (name != nullptr) {
    strlcpy(touchModel, name, sizeof(touchModel));
  }
  touch.reset();
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setMirrorXY(true, true);
  Serial.print("DASH_TOUCH_READY model=");
  Serial.print(touchModel);
  Serial.print(" points=");
  Serial.println(touch.getSupportTouchPoint());
  Serial.flush();
}

void updateSensors() {
  if (imuReady && qmi.getDataReady()) {
    qmi.getAccelerometer(acc.x, acc.y, acc.z);
    qmi.getGyroscope(gyr.x, gyr.y, gyr.z);
  }
}

void detectImuGesture() {
  if (!imuReady || powerMode == POWER_STANDBY) {
    return;
  }

  float magnitude = accMagnitude();
  float delta = fabsf(magnitude - previousAccMagnitude);
  previousAccMagnitude = magnitude;

  uint32_t now = millis();
  if (now - lastGestureMs < 1200) {
    return;
  }

  if (delta > 0.45f || maxAbsGyro() > 80.0f) {
    lastGestureMs = now;
    handleGesture("SHAKE", "imu");
  }
}

void enforceIdlePower() {
  if (powerMode != POWER_ACTIVE || idleDimMs == 0) {
    return;
  }
  if (millis() - lastActivityMs >= idleDimMs) {
    setPowerMode(POWER_DIM, "idle");
  }
}

void handleTouch() {
  if (!touchReady) {
    return;
  }

  uint8_t touched = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (touched == 0) {
    return;
  }

  markActivity();
  touchEvents++;
  DashboardPage nextPage = currentPage;
  if (touchX[0] < (LCD_WIDTH / 2)) {
    nextPage = static_cast<DashboardPage>((currentPage + 3) % 4);
  } else {
    nextPage = static_cast<DashboardPage>((currentPage + 1) % 4);
  }
  Serial.print("DASH_TOUCH_EVENT count=");
  Serial.print(touchEvents);
  Serial.print(" points=");
  Serial.print(touched);
  Serial.print(" x=");
  Serial.print(touchX[0]);
  Serial.print(" y=");
  Serial.println(touchY[0]);
  Serial.flush();
  setPage(nextPage, "touch");
  delay(220);
}

void handleCommand(String command) {
  command.trim();
  command.toUpperCase();
  if (command.length() == 0) {
    return;
  }
  if (command == "PING") {
    markActivity();
    Serial.println("PONG");
    Serial.flush();
    return;
  }
  if (command == "NEXT") {
    setPage(static_cast<DashboardPage>((currentPage + 1) % 4), "serial");
    return;
  }
  if (command == "PREV") {
    setPage(static_cast<DashboardPage>((currentPage + 3) % 4), "serial");
    return;
  }
  if (command.startsWith("GESTURE:")) {
    String gesture = command.substring(8);
    if (gesture == "SHAKE" || gesture == "TILT_LEFT" || gesture == "TILT_RIGHT") {
      handleGesture(gesture.c_str(), "serial");
    } else {
      Serial.print("DASH_BAD_GESTURE value=");
      Serial.println(gesture);
      Serial.flush();
    }
    return;
  }
  if (command.startsWith("BRIGHT:")) {
    int requested = command.substring(7).toInt();
    activeBrightness = static_cast<uint8_t>(constrain(requested, 8, 255));
    markActivity();
    applyBrightness();
    drawPage();
    emitPower("serial");
    return;
  }
  if (command.startsWith("IDLE:")) {
    long requestedIdle = command.substring(5).toInt();
    idleDimMs = static_cast<uint32_t>(requestedIdle < 0 ? 0 : requestedIdle);
    markActivity();
    emitPower("serial");
    return;
  }
  if (command == "POWER:STANDBY") {
    setPowerMode(POWER_STANDBY, "serial");
    return;
  }
  if (command == "POWER:DIM") {
    setPowerMode(POWER_DIM, "serial");
    return;
  }
  if (command == "POWER:WAKE" || command == "WAKE") {
    setPowerMode(POWER_ACTIVE, "serial");
    return;
  }
  if (command.startsWith("PAGE:")) {
    DashboardPage requested;
    if (parsePage(command.substring(5), requested)) {
      setPage(requested, "serial");
    } else {
      Serial.print("DASH_BAD_PAGE value=");
      Serial.println(command.substring(5));
      Serial.flush();
    }
    return;
  }

  Serial.print("DASH_UNKNOWN_COMMAND value=");
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
    if (serialBuffer.length() < 80) {
      serialBuffer += ch;
    } else {
      serialBuffer = "";
      Serial.println("DASH_COMMAND_TOO_LONG");
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

  Serial.println("interaction_dashboard boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupPmu();
  setupImu();
  setupTouch();
  lastActivityMs = millis();
  previousAccMagnitude = accMagnitude();

  drawPage();
  Serial.print((displayReady && pmuReady && imuReady && touchReady) ? "DASH_READY" : "DASH_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" pmu=");
  Serial.print(pmuReady ? 1 : 0);
  Serial.print(" imu=");
  Serial.print(imuReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.println(touchReady ? 1 : 0);
  emitPage("boot");
  emitStatus();
}

void loop() {
  readSerialCommands();
  updateSensors();
  detectImuGesture();
  enforceIdlePower();
  handleTouch();

  if ((frame % 10) == 0) {
    emitStatus();
  }
  if ((frame % 20) == 0) {
    drawPage();
  }

  frame++;
  delay(100);
}
