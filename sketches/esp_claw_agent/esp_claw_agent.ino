#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
#include <string.h>
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

enum AgentPage {
  PAGE_HOME = 0,
  PAGE_RULES,
  PAGE_MCP,
  PAGE_MEMORY,
};

struct Rule {
  char name[20];
  char event[28];
  char action[36];
  bool enabled;
};

struct MemoryItem {
  char tag[16];
  char text[48];
};

constexpr uint8_t MAX_RULES = 6;
constexpr uint8_t MAX_MEMORY = 6;
Rule rules[MAX_RULES] = {
  {"wrist_wake", "WRIST_RAISE", "TOOL:status.next", true},
  {"battery_dim", "BATTERY_LOW", "TOOL:display.dim", true},
};
MemoryItem memories[MAX_MEMORY];

bool displayReady = false;
bool touchReady = false;
uint32_t frame = 0;
uint32_t commandCount = 0;
uint32_t eventCount = 0;
uint32_t actionCount = 0;
uint32_t mcpCallCount = 0;
uint32_t mcpToolCount = 0;
uint32_t chatCount = 0;
uint32_t memoryCount = 0;
uint32_t luaRuleCount = 0;
uint32_t ruleCount = 2;
AgentPage currentPage = PAGE_HOME;
String serialBuffer;
int16_t touchX[5] = {0};
int16_t touchY[5] = {0};
char lastEvent[36] = "BOOT";
char lastThought[72] = "Ready";
char lastDecision[72] = "idle";
char lastAction[72] = "none";
char lastMemory[72] = "-";

const char *pageName(AgentPage page) {
  switch (page) {
    case PAGE_HOME:
      return "HOME";
    case PAGE_RULES:
      return "RULES";
    case PAGE_MCP:
      return "MCP";
    case PAGE_MEMORY:
      return "MEMORY";
  }
  return "HOME";
}

bool parsePage(const String &name, AgentPage &page) {
  if (name == "HOME" || name == "AGENT") {
    page = PAGE_HOME;
    return true;
  }
  if (name == "RULES" || name == "RULE") {
    page = PAGE_RULES;
    return true;
  }
  if (name == "MCP" || name == "TOOLS") {
    page = PAGE_MCP;
    return true;
  }
  if (name == "MEMORY" || name == "MEM") {
    page = PAGE_MEMORY;
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

uint16_t actionColor() {
  if (strncmp(lastAction, "TOOL:", 5) == 0) {
    return RGB565_GREEN;
  }
  if (strncmp(lastAction, "LLM:", 4) == 0) {
    return RGB565_YELLOW;
  }
  return RGB565_CYAN;
}

void drawPage() {
  if (!displayReady) {
    return;
  }

  switch (currentPage) {
    case PAGE_HOME:
      drawFrame(RGB565_CYAN);
      centerText("AGENT", 44, 5, RGB565_CYAN);
      centerText("OK", 130, 9, RGB565_WHITE);
      drawLine("event=", 292, RGB565_GREEN);
      gfx->print(lastEvent);
      drawLine("action=", 330, actionColor());
      gfx->print(lastAction);
      drawLine("rules=", 368, RGB565_GREEN);
      gfx->print(ruleCount);
      break;
    case PAGE_RULES:
      drawFrame(RGB565_GREEN);
      centerText("RULES", 44, 6, RGB565_CYAN);
      for (uint8_t i = 0; i < ruleCount && i < MAX_RULES; i++) {
        gfx->setTextSize(2);
        gfx->setTextColor(rules[i].enabled ? RGB565_GREEN : RGB565_YELLOW, RGB565_BLACK);
        gfx->setCursor(42, 140 + i * 44);
        gfx->print(rules[i].name);
        gfx->print(" ");
        gfx->print(rules[i].event);
      }
      break;
    case PAGE_MCP:
      drawFrame(RGB565_YELLOW);
      centerText("MCP", 54, 7, RGB565_CYAN);
      drawLine("server+client", 164, RGB565_WHITE);
      drawLine("calls=", 250, RGB565_GREEN);
      gfx->print(mcpCallCount);
      drawLine(lastAction, 312, actionColor());
      break;
    case PAGE_MEMORY:
      drawFrame(RGB565_CYAN);
      centerText("MEM", 54, 7, RGB565_CYAN);
      drawLine("jsonl tags", 164, RGB565_WHITE);
      drawLine("items=", 250, RGB565_GREEN);
      gfx->print(memoryCount);
      drawLine(lastMemory, 312, RGB565_YELLOW);
      break;
  }
}

void emitPage(const char *source) {
  Serial.print("CLAW_PAGE page=");
  Serial.print(pageName(currentPage));
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void setPage(AgentPage page, const char *source) {
  currentPage = page;
  drawPage();
  emitPage(source);
}

void emitCaps() {
  Serial.println("CLAW_CAPS loop=sense,reason,decide,act im=chat rules=lua_subset lua=load mcp=server,client memory=jsonl_tags,get tools=status.next,display.dim,light.toggle,display.message");
  Serial.flush();
}

void emitState() {
  Serial.print("CLAW_STATE frame=");
  Serial.print(frame);
  Serial.print(" page=");
  Serial.print(pageName(currentPage));
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" rules=");
  Serial.print(ruleCount);
  Serial.print(" events=");
  Serial.print(eventCount);
  Serial.print(" actions=");
  Serial.print(actionCount);
  Serial.print(" mcp=");
  Serial.print(mcpCallCount);
  Serial.print(" tools=");
  Serial.print(mcpToolCount);
  Serial.print(" chats=");
  Serial.print(chatCount);
  Serial.print(" memory=");
  Serial.print(memoryCount);
  Serial.print(" lua=");
  Serial.print(luaRuleCount);
  Serial.print(" decision=");
  Serial.print(lastDecision);
  Serial.print(" action=");
  Serial.println(lastAction);
  Serial.flush();
}

int findRuleForEvent(const String &eventName) {
  for (uint8_t i = 0; i < ruleCount && i < MAX_RULES; i++) {
    if (rules[i].enabled && eventName == rules[i].event) {
      return i;
    }
  }
  return -1;
}

void runAction(const char *action, const char *source) {
  actionCount++;
  strlcpy(lastAction, action, sizeof(lastAction));
  Serial.print("CLAW_ACT source=");
  Serial.print(source);
  Serial.print(" action=");
  Serial.print(action);
  Serial.print(" count=");
  Serial.println(actionCount);
  Serial.flush();
  drawPage();
}

void processEvent(const String &eventName, const String &value, const char *source) {
  eventCount++;
  copyString(lastEvent, sizeof(lastEvent), eventName);
  Serial.print("CLAW_SENSE source=");
  Serial.print(source);
  Serial.print(" event=");
  Serial.print(eventName);
  Serial.print(" value=");
  Serial.println(value);

  int ruleIndex = findRuleForEvent(eventName);
  if (ruleIndex >= 0) {
    snprintf(lastThought, sizeof(lastThought), "rule_match:%s", rules[ruleIndex].name);
    snprintf(lastDecision, sizeof(lastDecision), "rule:%s", rules[ruleIndex].name);
    Serial.print("CLAW_REASON source=rule event=");
    Serial.print(eventName);
    Serial.print(" rule=");
    Serial.println(rules[ruleIndex].name);
    Serial.print("CLAW_DECIDE source=rule rule=");
    Serial.print(rules[ruleIndex].name);
    Serial.print(" action=");
    Serial.println(rules[ruleIndex].action);
    runAction(rules[ruleIndex].action, "rule");
  } else {
    strlcpy(lastThought, "no_rule_escalate", sizeof(lastThought));
    strlcpy(lastDecision, "llm_request", sizeof(lastDecision));
    Serial.print("CLAW_REASON source=router event=");
    Serial.print(eventName);
    Serial.println(" rule=none");
    Serial.print("CLAW_DECIDE source=router action=LLM:REQUEST event=");
    Serial.println(eventName);
    runAction("LLM:REQUEST", "router");
  }
  Serial.flush();
  drawPage();
}

bool addRule(const String &payload) {
  if (ruleCount >= MAX_RULES) {
    Serial.println("CLAW_RULE_FULL");
    Serial.flush();
    return false;
  }
  int first = payload.indexOf(':');
  int second = payload.indexOf(':', first + 1);
  if (first <= 0 || second <= first + 1 || second >= static_cast<int>(payload.length()) - 1) {
    Serial.print("CLAW_BAD_RULE value=");
    Serial.println(payload);
    Serial.flush();
    return false;
  }

  copyString(rules[ruleCount].name, sizeof(rules[ruleCount].name), payload.substring(0, first));
  copyString(rules[ruleCount].event, sizeof(rules[ruleCount].event), payload.substring(first + 1, second));
  copyString(rules[ruleCount].action, sizeof(rules[ruleCount].action), payload.substring(second + 1));
  rules[ruleCount].enabled = true;
  ruleCount++;
  Serial.print("CLAW_RULE_ADDED name=");
  Serial.print(rules[ruleCount - 1].name);
  Serial.print(" event=");
  Serial.print(rules[ruleCount - 1].event);
  Serial.print(" action=");
  Serial.println(rules[ruleCount - 1].action);
  Serial.flush();
  drawPage();
  return true;
}

bool loadLuaRule(const String &payload) {
  bool added = addRule(payload);
  if (!added) {
    return false;
  }
  luaRuleCount++;
  Serial.print("CLAW_LUA_LOADED name=");
  Serial.print(rules[ruleCount - 1].name);
  Serial.print(" event=");
  Serial.print(rules[ruleCount - 1].event);
  Serial.print(" action=");
  Serial.print(rules[ruleCount - 1].action);
  Serial.print(" count=");
  Serial.println(luaRuleCount);
  Serial.flush();
  return true;
}

void registerMcpTool(const String &payload) {
  int split = payload.indexOf(':');
  String tool = split >= 0 ? payload.substring(0, split) : payload;
  String schema = split >= 0 ? payload.substring(split + 1) : "-";
  tool.trim();
  schema.trim();
  mcpToolCount++;
  Serial.print("CLAW_MCP_REGISTER tool=");
  Serial.print(tool);
  Serial.print(" schema=");
  Serial.print(schema.length() ? schema : "-");
  Serial.print(" count=");
  Serial.println(mcpToolCount);
  Serial.flush();
  strlcpy(lastDecision, "mcp_tool_registered", sizeof(lastDecision));
  setPage(PAGE_MCP, "mcp");
}

void processMcpCall(const String &payload) {
  int split = payload.indexOf(':');
  String tool = split >= 0 ? payload.substring(0, split) : payload;
  String arg = split >= 0 ? payload.substring(split + 1) : "";
  tool.trim();
  arg.trim();
  mcpCallCount++;
  Serial.print("CLAW_MCP_CALL tool=");
  Serial.print(tool);
  Serial.print(" arg=");
  Serial.print(arg.length() ? arg : "-");
  Serial.print(" count=");
  Serial.println(mcpCallCount);
  String action = "TOOL:" + tool;
  runAction(action.c_str(), "mcp");
}

void processChat(const String &message) {
  chatCount++;
  Serial.print("CLAW_CHAT source=im text=");
  Serial.println(message);
  if (message.indexOf("battery") >= 0 || message.indexOf("BATTERY") >= 0) {
    addRule("chat_battery:BATTERY_LOW:TOOL:display.dim");
    strlcpy(lastDecision, "chat_generated_rule", sizeof(lastDecision));
  } else {
    strlcpy(lastDecision, "chat_ack", sizeof(lastDecision));
  }
  drawPage();
}

void putMemory(const String &payload) {
  int split = payload.indexOf(':');
  if (split <= 0 || split >= static_cast<int>(payload.length()) - 1) {
    Serial.print("CLAW_BAD_MEMORY value=");
    Serial.println(payload);
    Serial.flush();
    return;
  }
  String tag = payload.substring(0, split);
  String text = payload.substring(split + 1);
  tag.trim();
  text.trim();
  if (memoryCount < MAX_MEMORY) {
    copyString(memories[memoryCount].tag, sizeof(memories[memoryCount].tag), tag);
    copyString(memories[memoryCount].text, sizeof(memories[memoryCount].text), text);
  }
  memoryCount++;
  String item = tag + "=" + text;
  copyString(lastMemory, sizeof(lastMemory), item);
  Serial.print("CLAW_MEMORY_PUT tag=");
  Serial.print(tag);
  Serial.print(" text=");
  Serial.print(text);
  Serial.print(" count=");
  Serial.println(memoryCount);
  Serial.flush();
  drawPage();
}

void getMemory(const String &tagPayload) {
  String tag = tagPayload;
  tag.trim();
  int found = -1;
  uint32_t limit = min(memoryCount, static_cast<uint32_t>(MAX_MEMORY));
  for (uint32_t i = 0; i < limit; i++) {
    if (tag == memories[i].tag) {
      found = static_cast<int>(i);
      break;
    }
  }
  Serial.print("CLAW_MEMORY_GET tag=");
  Serial.print(tag);
  Serial.print(" hit=");
  Serial.print(found >= 0 ? 1 : 0);
  Serial.print(" text=");
  Serial.println(found >= 0 ? memories[found].text : "-");
  Serial.flush();
  setPage(PAGE_MEMORY, "memory");
}

void handleCommand(String command) {
  command.trim();
  if (command.length() == 0) {
    return;
  }
  commandCount++;
  String upper = command;
  upper.toUpperCase();

  if (upper == "PING") {
    Serial.println("PONG");
    Serial.flush();
    return;
  }
  if (upper == "CAPS?") {
    emitCaps();
    return;
  }
  if (upper == "STATE?") {
    emitState();
    return;
  }
  if (upper.startsWith("PAGE:")) {
    AgentPage page;
    String name = upper.substring(5);
    if (parsePage(name, page)) {
      setPage(page, "serial");
    } else {
      Serial.print("CLAW_BAD_PAGE value=");
      Serial.println(name);
      Serial.flush();
    }
    return;
  }
  if (upper.startsWith("RULE:ADD:")) {
    addRule(command.substring(9));
    return;
  }
  if (upper.startsWith("LUA:LOAD:")) {
    loadLuaRule(command.substring(9));
    return;
  }
  if (upper.startsWith("EVENT:")) {
    String payload = command.substring(6);
    int split = payload.indexOf(':');
    String eventName = split >= 0 ? payload.substring(0, split) : payload;
    String value = split >= 0 ? payload.substring(split + 1) : "-";
    eventName.trim();
    value.trim();
    eventName.toUpperCase();
    processEvent(eventName, value, "serial");
    return;
  }
  if (upper.startsWith("MCP:CALL:")) {
    processMcpCall(command.substring(9));
    return;
  }
  if (upper.startsWith("MCP:REGISTER:")) {
    registerMcpTool(command.substring(13));
    return;
  }
  if (upper.startsWith("CHAT:")) {
    processChat(command.substring(5));
    return;
  }
  if (upper.startsWith("MEM:PUT:")) {
    putMemory(command.substring(8));
    return;
  }
  if (upper.startsWith("MEM:GET:")) {
    getMemory(command.substring(8));
    return;
  }

  Serial.print("CLAW_UNKNOWN_COMMAND value=");
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
    if (serialBuffer.length() < 160) {
      serialBuffer += ch;
    } else {
      serialBuffer = "";
      Serial.println("CLAW_COMMAND_TOO_LONG");
      Serial.flush();
    }
  }
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("CLAW_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(DISPLAY_BRIGHTNESS);
  displayReady = true;
  drawPage();
}

void setupTouch() {
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!touchReady) {
    Serial.println("CLAW_TOUCH_FAILED");
    Serial.flush();
    return;
  }
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setSwapXY(true);
  touch.setMirrorXY(false, true);
  Serial.println("CLAW_TOUCH_READY");
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
  AgentPage next = static_cast<AgentPage>((static_cast<uint8_t>(currentPage) + 1) % 4);
  setPage(next, "touch");
  delay(260);
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("esp_claw_agent boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();
  emitCaps();
  Serial.print((displayReady && touchReady) ? "CLAW_READY" : "CLAW_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" rules=");
  Serial.println(ruleCount);
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
