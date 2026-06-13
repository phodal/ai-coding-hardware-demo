#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
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

enum PowerMode {
  POWER_ACTIVE,
  POWER_DIM,
  POWER_STANDBY,
};

struct PowerSample {
  uint16_t battMv;
  uint16_t vbusMv;
  uint16_t systemMv;
  int batteryPct;
  bool batteryConnected;
  bool charging;
  bool discharging;
  bool vbusIn;
  int chargerStatus;
  float tempC;
  int estimateMin;
};

bool displayReady = false;
bool pmuReady = false;
uint32_t frame = 0;
uint32_t sampleCount = 0;
uint32_t profileCount = 0;
uint32_t modeChanges = 0;
uint32_t wakeCount = 0;
PowerMode currentMode = POWER_ACTIVE;
uint8_t activeBrightness = 200;
uint8_t dimBrightness = 24;
uint8_t standbyBrightness = 0;
int capacityMah = 350;
int activeLoadMa = 160;
int dimLoadMa = 55;
int standbyLoadMa = 12;

const char *modeName(PowerMode mode) {
  switch (mode) {
    case POWER_ACTIVE:
      return "ACTIVE";
    case POWER_DIM:
      return "DIM";
    case POWER_STANDBY:
      return "STANDBY";
  }
  return "UNKNOWN";
}

int currentLoadMa() {
  switch (currentMode) {
    case POWER_ACTIVE:
      return activeLoadMa;
    case POWER_DIM:
      return dimLoadMa;
    case POWER_STANDBY:
      return standbyLoadMa;
  }
  return activeLoadMa;
}

uint8_t currentBrightness() {
  switch (currentMode) {
    case POWER_ACTIVE:
      return activeBrightness;
    case POWER_DIM:
      return dimBrightness;
    case POWER_STANDBY:
      return standbyBrightness;
  }
  return activeBrightness;
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

int pctFromVoltage(uint16_t battMv) {
  if (battMv < 3000) {
    return 0;
  }
  if (battMv > 4200) {
    return 100;
  }
  return map(battMv, 3300, 4200, 0, 100);
}

PowerSample readPowerSample() {
  PowerSample sample;
  sample.battMv = pmuReady ? power.getBattVoltage() : 0;
  sample.vbusMv = pmuReady ? power.getVbusVoltage() : 0;
  sample.systemMv = pmuReady ? power.getSystemVoltage() : 0;
  sample.batteryConnected = pmuReady && power.isBatteryConnect();
  sample.batteryPct = sample.batteryConnected ? power.getBatteryPercent() : -1;
  sample.charging = pmuReady && power.isCharging();
  sample.discharging = pmuReady && power.isDischarge();
  sample.vbusIn = pmuReady && power.isVbusIn();
  sample.chargerStatus = pmuReady ? static_cast<int>(power.getChargerStatus()) : -1;
  sample.tempC = pmuReady ? power.getTemperature() : 0.0f;

  int pct = sample.batteryPct >= 0 ? sample.batteryPct : pctFromVoltage(sample.battMv);
  pct = constrain(pct, 0, 100);
  int loadMa = max(currentLoadMa(), 1);
  sample.estimateMin = (capacityMah * pct * 60) / (100 * loadMa);
  return sample;
}

void drawPowerScreen(const PowerSample &sample) {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, RGB565_GREEN);
  centerText("PWR", 42, 7, RGB565_YELLOW);
  centerText(pmuReady ? "OK" : "WAIT", 128, 9, RGB565_WHITE);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_CYAN, RGB565_BLACK);
  gfx->setCursor(46, 260);
  gfx->print("MODE ");
  gfx->print(modeName(currentMode));

  gfx->setTextColor(RGB565_GREEN, RGB565_BLACK);
  gfx->setCursor(46, 296);
  gfx->print("SYS ");
  gfx->print(sample.systemMv);
  gfx->print("mV");

  gfx->setCursor(46, 330);
  gfx->print("VBUS ");
  gfx->print(sample.vbusMv);
  gfx->print("mV");

  gfx->setCursor(46, 364);
  gfx->print("BATT ");
  if (sample.batteryPct >= 0) {
    gfx->print(sample.batteryPct);
    gfx->print("% ");
  } else {
    gfx->print("--% ");
  }
  gfx->print(sample.battMv);
  gfx->print("mV");

  gfx->setCursor(46, 398);
  gfx->print("EST ");
  gfx->print(sample.estimateMin);
  gfx->print("min");
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
    Serial.println("POWER_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  displayReady = true;
  gfx->setBrightness(activeBrightness);
}

void setupPmu() {
  pmuReady = power.begin(Wire, AXP2101_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!pmuReady) {
    Serial.println("POWER_PMU_FAILED");
    Serial.flush();
    return;
  }

  power.disableIRQ(XPOWERS_AXP2101_ALL_IRQ);
  power.clearIrqStatus();
  power.setChargeTargetVoltage(3);
  enablePmuAdc();
  Serial.println("POWER_PMU_READY");
  Serial.flush();
}

void emitProfile() {
  profileCount++;
  Serial.print("POWER_PROFILE capacity_mah=");
  Serial.print(capacityMah);
  Serial.print(" active_ma=");
  Serial.print(activeLoadMa);
  Serial.print(" dim_ma=");
  Serial.print(dimLoadMa);
  Serial.print(" standby_ma=");
  Serial.print(standbyLoadMa);
  Serial.print(" profile_count=");
  Serial.println(profileCount);
  Serial.flush();
}

void emitSample() {
  PowerSample sample = readPowerSample();
  sampleCount++;
  Serial.print("POWER_SAMPLE frame=");
  Serial.print(frame);
  Serial.print(" pmu=");
  Serial.print(pmuReady ? 1 : 0);
  Serial.print(" mode=");
  Serial.print(modeName(currentMode));
  Serial.print(" system_mv=");
  Serial.print(sample.systemMv);
  Serial.print(" vbus_mv=");
  Serial.print(sample.vbusMv);
  Serial.print(" batt_mv=");
  Serial.print(sample.battMv);
  Serial.print(" battery_pct=");
  Serial.print(sample.batteryPct);
  Serial.print(" battery_connected=");
  Serial.print(sample.batteryConnected ? 1 : 0);
  Serial.print(" charging=");
  Serial.print(sample.charging ? 1 : 0);
  Serial.print(" discharging=");
  Serial.print(sample.discharging ? 1 : 0);
  Serial.print(" vbus_in=");
  Serial.print(sample.vbusIn ? 1 : 0);
  Serial.print(" charger=");
  Serial.print(sample.chargerStatus);
  Serial.print(" temp_c=");
  Serial.print(sample.tempC, 2);
  Serial.print(" estimate_min=");
  Serial.print(sample.estimateMin);
  Serial.print(" sample_count=");
  Serial.println(sampleCount);
  Serial.flush();
}

void emitState() {
  Serial.print("POWER_STATE display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" pmu=");
  Serial.print(pmuReady ? 1 : 0);
  Serial.print(" mode=");
  Serial.print(modeName(currentMode));
  Serial.print(" brightness=");
  Serial.print(currentBrightness());
  Serial.print(" sample_count=");
  Serial.print(sampleCount);
  Serial.print(" profile_count=");
  Serial.print(profileCount);
  Serial.print(" mode_changes=");
  Serial.print(modeChanges);
  Serial.print(" wake_count=");
  Serial.println(wakeCount);
  Serial.flush();
}

void applyPowerMode(PowerMode nextMode, const char *source) {
  if (currentMode != nextMode) {
    modeChanges++;
  }
  if (currentMode == POWER_STANDBY && nextMode != POWER_STANDBY) {
    wakeCount++;
  }
  currentMode = nextMode;
  if (displayReady) {
    gfx->setBrightness(currentBrightness());
  }

  Serial.print("POWER_MODE mode=");
  Serial.print(modeName(currentMode));
  Serial.print(" brightness=");
  Serial.print(currentBrightness());
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();

  PowerSample sample = readPowerSample();
  drawPowerScreen(sample);
  emitState();
}

void handleCommand(String line) {
  line.trim();
  if (line.length() == 0) {
    return;
  }
  line.toUpperCase();

  if (line == "PING") {
    Serial.println("PONG");
    Serial.flush();
  } else if (line == "STATE?") {
    emitState();
  } else if (line == "SAMPLE?") {
    emitSample();
  } else if (line == "PROFILE?") {
    emitProfile();
  } else if (line == "MODE:ACTIVE" || line == "WAKE") {
    applyPowerMode(POWER_ACTIVE, "serial");
  } else if (line == "MODE:DIM") {
    applyPowerMode(POWER_DIM, "serial");
  } else if (line == "MODE:STANDBY" || line == "SLEEP") {
    applyPowerMode(POWER_STANDBY, "serial");
  } else if (line.startsWith("BRIGHT:")) {
    int value = constrain(line.substring(7).toInt(), 0, 255);
    activeBrightness = static_cast<uint8_t>(value);
    if (currentMode == POWER_ACTIVE && displayReady) {
      gfx->setBrightness(activeBrightness);
    }
    applyPowerMode(POWER_ACTIVE, "brightness");
  } else if (line.startsWith("CAPACITY:")) {
    int value = line.substring(9).toInt();
    if (value > 0 && value < 20000) {
      capacityMah = value;
    }
    emitProfile();
  } else if (line.startsWith("LOAD:")) {
    int active;
    int dim;
    int standby;
    if (sscanf(line.substring(5).c_str(), "%d,%d,%d", &active, &dim, &standby) == 3) {
      if (active > 0 && dim > 0 && standby > 0) {
        activeLoadMa = active;
        dimLoadMa = dim;
        standbyLoadMa = standby;
      }
    }
    emitProfile();
  } else {
    Serial.print("POWER_ERROR unknown_command=");
    Serial.println(line);
    Serial.flush();
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(20);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("power_lifecycle_probe boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupPmu();

  PowerSample sample = readPowerSample();
  drawPowerScreen(sample);
  Serial.println(pmuReady ? "POWER_READY" : "POWER_PARTIAL");
  emitState();
  emitProfile();
  emitSample();
}

void loop() {
  while (Serial.available() > 0) {
    handleCommand(Serial.readStringUntil('\n'));
  }

  if ((frame % 20) == 0) {
    PowerSample sample = readPowerSample();
    drawPowerScreen(sample);
  }

  if ((frame % 30) == 0) {
    emitSample();
  }

  frame++;
  delay(100);
}
