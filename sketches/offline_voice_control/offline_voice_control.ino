#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
#include <string.h>
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

TouchDrvCST92xx touch;

enum VoicePage {
  PAGE_HOME = 0,
  PAGE_COMMANDS,
  PAGE_STATE,
  PAGE_LOG,
};

struct VoiceCommand {
  char id[24];
  char phrase[36];
  char action[36];
  bool enabled;
};

constexpr uint8_t MAX_COMMANDS = 10;
VoiceCommand commands[MAX_COMMANDS] = {
  {"LIGHT_ON", "turn on light", "LIGHT:ON", true},
  {"LIGHT_OFF", "turn off light", "LIGHT:OFF", true},
  {"NEXT_PAGE", "next page", "UI:NEXT_PAGE", true},
  {"SLEEP", "go to sleep", "POWER:SLEEP", true},
};

bool displayReady = false;
bool touchReady = false;
bool wakeActive = false;
bool continuousMode = false;
bool lightOn = false;
bool asleep = false;
uint8_t brightness = 200;
uint8_t commandCount = 4;
uint32_t frame = 0;
uint32_t wakeCount = 0;
uint32_t recognizedCount = 0;
uint32_t rejectedCount = 0;
uint32_t actionCount = 0;
uint32_t commandLineCount = 0;
VoicePage currentPage = PAGE_HOME;
String serialBuffer;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};
char lastWake[24] = "-";
char lastCommand[28] = "-";
char lastPhrase[44] = "-";
char lastAction[44] = "-";
char lastReject[48] = "-";

const char *pageName(VoicePage page) {
  switch (page) {
    case PAGE_HOME:
      return "HOME";
    case PAGE_COMMANDS:
      return "COMMANDS";
    case PAGE_STATE:
      return "STATE";
    case PAGE_LOG:
      return "LOG";
  }
  return "HOME";
}

bool parsePage(const String &name, VoicePage &page) {
  if (name == "HOME" || name == "VOICE") {
    page = PAGE_HOME;
    return true;
  }
  if (name == "COMMANDS" || name == "CMD") {
    page = PAGE_COMMANDS;
    return true;
  }
  if (name == "STATE") {
    page = PAGE_STATE;
    return true;
  }
  if (name == "LOG") {
    page = PAGE_LOG;
    return true;
  }
  return false;
}

void copyString(char *target, size_t targetSize, const String &value) {
  String sanitized = value;
  sanitized.replace("\r", " ");
  sanitized.replace("\n", " ");
  sanitized.trim();
  strlcpy(target, sanitized.c_str(), targetSize);
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

void drawLine(const char *label, int16_t y, uint16_t color) {
  gfx->setTextSize(2);
  gfx->setTextColor(color, RGB565_BLACK);
  gfx->setCursor(42, y);
  gfx->print(label);
}

void drawFrame(uint16_t color) {
  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, color);
}

uint16_t statusColor() {
  if (asleep) {
    return RGB565_YELLOW;
  }
  return wakeActive || continuousMode ? RGB565_GREEN : RGB565_CYAN;
}

uint8_t enabledCommandCount() {
  uint8_t count = 0;
  for (uint8_t i = 0; i < commandCount && i < MAX_COMMANDS; i++) {
    if (commands[i].enabled) {
      count++;
    }
  }
  return count;
}

void drawPage() {
  if (!displayReady) {
    return;
  }

  switch (currentPage) {
    case PAGE_HOME:
      drawFrame(statusColor());
      centerText("VOICE", 42, 6, RGB565_CYAN);
      centerText("OK", 130, 9, RGB565_WHITE);
      drawLine("wake=", 292, RGB565_GREEN);
      gfx->print(wakeActive ? "ON" : "OFF");
      drawLine("cmd=", 330, RGB565_GREEN);
      gfx->print(lastCommand);
      drawLine("action=", 368, RGB565_YELLOW);
      gfx->print(lastAction);
      break;
    case PAGE_COMMANDS:
      drawFrame(RGB565_GREEN);
      centerText("COMMAND", 42, 5, RGB565_CYAN);
      for (uint8_t i = 0; i < commandCount && i < 5; i++) {
        gfx->setTextSize(2);
        gfx->setTextColor(commands[i].enabled ? RGB565_GREEN : RGB565_YELLOW, RGB565_BLACK);
        gfx->setCursor(34, 132 + i * 46);
        gfx->print(commands[i].id);
        gfx->print(" ");
        gfx->print(commands[i].action);
      }
      break;
    case PAGE_STATE:
      drawFrame(RGB565_CYAN);
      centerText("STATE", 48, 6, RGB565_CYAN);
      drawLine("light=", 164, RGB565_GREEN);
      gfx->print(lightOn ? "ON" : "OFF");
      drawLine("sleep=", 214, RGB565_GREEN);
      gfx->print(asleep ? "YES" : "NO");
      drawLine("mode=", 264, RGB565_GREEN);
      gfx->print(continuousMode ? "CONT" : "SINGLE");
      drawLine("hits=", 314, RGB565_YELLOW);
      gfx->print(recognizedCount);
      break;
    case PAGE_LOG:
      drawFrame(RGB565_YELLOW);
      centerText("LOG", 54, 7, RGB565_CYAN);
      drawLine(lastWake, 150, RGB565_GREEN);
      drawLine(lastPhrase, 210, RGB565_WHITE);
      drawLine(lastReject, 270, RGB565_YELLOW);
      break;
  }
}

void emitPage(const char *source) {
  Serial.print("VOICE_PAGE page=");
  Serial.print(pageName(currentPage));
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void setPage(VoicePage page, const char *source) {
  currentPage = page;
  drawPage();
  emitPage(source);
}

void emitModel() {
  Serial.println("VOICE_MODEL wake_engine=WakeNet(serial_sim) command_engine=MultiNet(serial_sim) mode=offline languages=en,zh commands_runtime=add,delete,modify max_commands=10");
  Serial.flush();
}

void emitCommands() {
  Serial.print("VOICE_COMMANDS count=");
  Serial.println(commandCount);
  for (uint8_t i = 0; i < commandCount && i < MAX_COMMANDS; i++) {
    Serial.print("VOICE_COMMAND id=");
    Serial.print(commands[i].id);
    Serial.print(" phrase=");
    Serial.print(commands[i].phrase);
    Serial.print(" action=");
    Serial.print(commands[i].action);
    Serial.print(" enabled=");
    Serial.println(commands[i].enabled ? 1 : 0);
  }
  Serial.flush();
}

void emitState() {
  Serial.print("VOICE_STATE frame=");
  Serial.print(frame);
  Serial.print(" page=");
  Serial.print(pageName(currentPage));
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" wake=");
  Serial.print(wakeActive ? 1 : 0);
  Serial.print(" mode=");
  Serial.print(continuousMode ? "CONTINUOUS" : "SINGLE");
  Serial.print(" commands=");
  Serial.print(commandCount);
  Serial.print(" enabled=");
  Serial.print(enabledCommandCount());
  Serial.print(" recognized=");
  Serial.print(recognizedCount);
  Serial.print(" rejected=");
  Serial.print(rejectedCount);
  Serial.print(" actions=");
  Serial.print(actionCount);
  Serial.print(" light=");
  Serial.print(lightOn ? 1 : 0);
  Serial.print(" asleep=");
  Serial.print(asleep ? 1 : 0);
  Serial.print(" last=");
  Serial.println(lastCommand);
  Serial.flush();
}

int findCommand(const String &needle) {
  String normalized = needle;
  normalized.trim();
  normalized.toUpperCase();
  for (uint8_t i = 0; i < commandCount && i < MAX_COMMANDS; i++) {
    String id = commands[i].id;
    id.toUpperCase();
    String phrase = commands[i].phrase;
    phrase.toUpperCase();
    if (commands[i].enabled && (normalized == id || normalized == phrase)) {
      return i;
    }
  }
  return -1;
}

void runAction(const char *action, const char *source) {
  actionCount++;
  strlcpy(lastAction, action, sizeof(lastAction));
  if (strcmp(action, "LIGHT:ON") == 0) {
    lightOn = true;
  } else if (strcmp(action, "LIGHT:OFF") == 0) {
    lightOn = false;
  } else if (strcmp(action, "UI:NEXT_PAGE") == 0) {
    currentPage = static_cast<VoicePage>((static_cast<uint8_t>(currentPage) + 1) % 4);
  } else if (strcmp(action, "POWER:SLEEP") == 0) {
    asleep = true;
    wakeActive = false;
    brightness = 60;
    if (displayReady) {
      gfx->setBrightness(brightness);
    }
  } else if (strcmp(action, "POWER:WAKE") == 0) {
    asleep = false;
    brightness = 200;
    if (displayReady) {
      gfx->setBrightness(brightness);
    }
  }

  Serial.print("VOICE_ACTION source=");
  Serial.print(source);
  Serial.print(" action=");
  Serial.print(action);
  Serial.print(" count=");
  Serial.println(actionCount);
  Serial.flush();
  drawPage();
}

void rejectCommand(const String &reason, const String &value) {
  rejectedCount++;
  String message = reason + ":" + value;
  copyString(lastReject, sizeof(lastReject), message);
  Serial.print("VOICE_REJECT reason=");
  Serial.print(reason);
  Serial.print(" value=");
  Serial.print(value);
  Serial.print(" count=");
  Serial.println(rejectedCount);
  Serial.flush();
  drawPage();
}

void handleWake(const String &word) {
  wakeActive = true;
  asleep = false;
  brightness = 200;
  if (displayReady) {
    gfx->setBrightness(brightness);
  }
  wakeCount++;
  copyString(lastWake, sizeof(lastWake), word);
  strlcpy(lastReject, "-", sizeof(lastReject));
  Serial.print("VOICE_WAKE engine=WakeNet source=serial word=");
  Serial.print(word);
  Serial.print(" count=");
  Serial.println(wakeCount);
  Serial.flush();
  drawPage();
}

void handleCommandWord(const String &value) {
  if (!wakeActive && !continuousMode) {
    rejectCommand("not_awake", value);
    return;
  }
  int index = findCommand(value);
  if (index < 0) {
    rejectCommand("unknown_command", value);
    return;
  }

  recognizedCount++;
  strlcpy(lastCommand, commands[index].id, sizeof(lastCommand));
  strlcpy(lastPhrase, commands[index].phrase, sizeof(lastPhrase));
  Serial.print("VOICE_CMD engine=MultiNet source=serial id=");
  Serial.print(commands[index].id);
  Serial.print(" phrase=");
  Serial.print(commands[index].phrase);
  Serial.print(" confidence=0.93 count=");
  Serial.println(recognizedCount);
  Serial.flush();
  runAction(commands[index].action, "multinet");
  if (!continuousMode) {
    wakeActive = false;
  }
  drawPage();
}

bool addCommand(const String &payload) {
  if (commandCount >= MAX_COMMANDS) {
    Serial.println("VOICE_COMMAND_FULL");
    Serial.flush();
    return false;
  }
  int first = payload.indexOf(':');
  int second = payload.indexOf(':', first + 1);
  if (first <= 0 || second <= first + 1 || second >= static_cast<int>(payload.length()) - 1) {
    Serial.print("VOICE_BAD_ADDCMD value=");
    Serial.println(payload);
    Serial.flush();
    return false;
  }
  copyString(commands[commandCount].id, sizeof(commands[commandCount].id), payload.substring(0, first));
  copyString(commands[commandCount].phrase, sizeof(commands[commandCount].phrase), payload.substring(first + 1, second));
  copyString(commands[commandCount].action, sizeof(commands[commandCount].action), payload.substring(second + 1));
  commands[commandCount].enabled = true;
  commandCount++;
  Serial.print("VOICE_COMMAND_ADDED id=");
  Serial.print(commands[commandCount - 1].id);
  Serial.print(" phrase=");
  Serial.print(commands[commandCount - 1].phrase);
  Serial.print(" action=");
  Serial.println(commands[commandCount - 1].action);
  Serial.flush();
  drawPage();
  return true;
}

bool modifyCommand(const String &payload) {
  int first = payload.indexOf(':');
  int second = payload.indexOf(':', first + 1);
  if (first <= 0 || second <= first + 1 || second >= static_cast<int>(payload.length()) - 1) {
    Serial.print("VOICE_BAD_MODCMD value=");
    Serial.println(payload);
    Serial.flush();
    return false;
  }

  String id = payload.substring(0, first);
  int index = findCommand(id);
  if (index < 0) {
    Serial.print("VOICE_COMMAND_MISSING id=");
    Serial.println(id);
    Serial.flush();
    return false;
  }

  copyString(commands[index].phrase, sizeof(commands[index].phrase), payload.substring(first + 1, second));
  copyString(commands[index].action, sizeof(commands[index].action), payload.substring(second + 1));
  commands[index].enabled = true;
  Serial.print("VOICE_COMMAND_MODIFIED id=");
  Serial.print(commands[index].id);
  Serial.print(" phrase=");
  Serial.print(commands[index].phrase);
  Serial.print(" action=");
  Serial.println(commands[index].action);
  Serial.flush();
  drawPage();
  return true;
}

bool deleteCommand(const String &idPayload) {
  String id = idPayload;
  id.trim();
  int index = findCommand(id);
  if (index < 0) {
    Serial.print("VOICE_COMMAND_MISSING id=");
    Serial.println(id);
    Serial.flush();
    return false;
  }

  commands[index].enabled = false;
  Serial.print("VOICE_COMMAND_DELETED id=");
  Serial.print(commands[index].id);
  Serial.print(" enabled=");
  Serial.println(commands[index].enabled ? 1 : 0);
  Serial.flush();
  drawPage();
  return true;
}

void handleCommandLine(String command) {
  command.trim();
  if (command.length() == 0) {
    return;
  }
  commandLineCount++;
  String upper = command;
  upper.toUpperCase();

  if (upper == "PING") {
    Serial.println("PONG");
    Serial.flush();
    return;
  }
  if (upper == "MODEL?") {
    emitModel();
    return;
  }
  if (upper == "COMMANDS?") {
    emitCommands();
    return;
  }
  if (upper == "STATE?") {
    emitState();
    return;
  }
  if (upper.startsWith("PAGE:")) {
    VoicePage page;
    String name = upper.substring(5);
    if (parsePage(name, page)) {
      setPage(page, "serial");
    } else {
      Serial.print("VOICE_BAD_PAGE value=");
      Serial.println(name);
      Serial.flush();
    }
    return;
  }
  if (upper == "MODE:CONTINUOUS") {
    continuousMode = true;
    Serial.println("VOICE_MODE mode=CONTINUOUS");
    Serial.flush();
    drawPage();
    return;
  }
  if (upper == "MODE:SINGLE") {
    continuousMode = false;
    Serial.println("VOICE_MODE mode=SINGLE");
    Serial.flush();
    drawPage();
    return;
  }
  if (upper.startsWith("WAKE:")) {
    handleWake(command.substring(5));
    return;
  }
  if (upper.startsWith("CMD:")) {
    handleCommandWord(command.substring(4));
    return;
  }
  if (upper.startsWith("ADDCMD:")) {
    addCommand(command.substring(7));
    return;
  }
  if (upper.startsWith("MODCMD:")) {
    modifyCommand(command.substring(7));
    return;
  }
  if (upper.startsWith("DELCMD:")) {
    deleteCommand(command.substring(7));
    return;
  }
  if (upper == "SLEEP") {
    runAction("POWER:SLEEP", "serial");
    return;
  }
  if (upper == "WAKE") {
    runAction("POWER:WAKE", "serial");
    wakeActive = true;
    return;
  }

  Serial.print("VOICE_UNKNOWN_COMMAND value=");
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
      handleCommandLine(serialBuffer);
      serialBuffer = "";
      continue;
    }
    if (serialBuffer.length() < 160) {
      serialBuffer += ch;
    } else {
      serialBuffer = "";
      Serial.println("VOICE_COMMAND_TOO_LONG");
      Serial.flush();
    }
  }
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("VOICE_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(brightness);
  displayReady = true;
  drawPage();
}

void setupTouch() {
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!touchReady) {
    Serial.println("VOICE_TOUCH_FAILED");
    Serial.flush();
    return;
  }
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setSwapXY(true);
  touch.setMirrorXY(false, true);
  Serial.println("VOICE_TOUCH_READY");
  Serial.flush();
}

void updateTouch() {
  if (!touchReady || !touch.isPressed()) {
    return;
  }
  uint8_t points = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (points == 0) {
    return;
  }
  VoicePage next = static_cast<VoicePage>((static_cast<uint8_t>(currentPage) + 1) % 4);
  setPage(next, "touch");
  delay(260);
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("offline_voice_control boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();
  emitModel();
  Serial.print((displayReady && touchReady) ? "VOICE_READY" : "VOICE_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" commands=");
  Serial.println(commandCount);
  Serial.flush();
  emitState();
}

void loop() {
  readSerialCommands();
  updateTouch();
  if ((frame % 50) == 0) {
    emitState();
  }
  frame++;
  delay(100);
}
