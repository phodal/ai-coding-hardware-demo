#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <TouchDrvCSTXXX.hpp>
#include <Wire.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <lvgl.h>
#include "lv_conf.h"
#include "pin_config.h"

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

#define LVGL_TICK_PERIOD_MS 2

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

TouchDrvCST92xx touch;
lv_disp_draw_buf_t drawBuf;
lv_color_t *lvBuf1 = nullptr;
lv_color_t *lvBuf2 = nullptr;
uint32_t screenWidth = 0;
uint32_t screenHeight = 0;

enum VisualPage {
  PAGE_CHAT = 0,
  PAGE_CARDS,
  PAGE_SETTINGS,
};

bool displayReady = false;
bool touchReady = false;
bool lvglReady = false;
uint32_t frame = 0;
uint32_t commandCount = 0;
uint32_t chatCount = 0;
uint32_t cardCount = 0;
uint32_t settingCount = 0;
uint32_t agentEvents = 0;
VisualPage currentPage = PAGE_CHAT;
String serialBuffer;
char lastChat[96] = "Ready";
char lastCard[64] = "none";
char lastSetting[64] = "none";
char agentThought[96] = "waiting";

lv_obj_t *tabview = nullptr;
lv_obj_t *chatTab = nullptr;
lv_obj_t *cardsTab = nullptr;
lv_obj_t *settingsTab = nullptr;
lv_obj_t *titleLabel = nullptr;
lv_obj_t *chatLogLabel = nullptr;
lv_obj_t *agentLabel = nullptr;
lv_obj_t *cardStatusLabel = nullptr;
lv_obj_t *cardListLabel = nullptr;
lv_obj_t *settingsLabel = nullptr;
lv_obj_t *settingListLabel = nullptr;
lv_obj_t *statsLabel = nullptr;

int16_t touchX[5] = {0};
int16_t touchY[5] = {0};

const char *pageName(VisualPage page) {
  switch (page) {
    case PAGE_CHAT:
      return "CHAT";
    case PAGE_CARDS:
      return "CARDS";
    case PAGE_SETTINGS:
      return "SETTINGS";
  }
  return "CHAT";
}

bool parsePage(const String &name, VisualPage &page) {
  if (name == "CHAT" || name == "HOME" || name == "AGENT") {
    page = PAGE_CHAT;
    return true;
  }
  if (name == "CARDS" || name == "CARD") {
    page = PAGE_CARDS;
    return true;
  }
  if (name == "SETTINGS" || name == "SETTING") {
    page = PAGE_SETTINGS;
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

void lvglRounderCb(struct _lv_disp_drv_t *disp_drv, lv_area_t *area) {
  (void)disp_drv;
  if (area->x1 % 2 != 0) {
    area->x1--;
  }
  if (area->y1 % 2 != 0) {
    area->y1--;
  }
  if (area->x2 % 2 == 0) {
    area->x2++;
  }
  if (area->y2 % 2 == 0) {
    area->y2++;
  }
}

void lvglFlush(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *colorP) {
  uint32_t width = area->x2 - area->x1 + 1;
  uint32_t height = area->y2 - area->y1 + 1;
#if (LV_COLOR_16_SWAP != 0)
  gfx->draw16bitBeRGBBitmap(area->x1, area->y1, reinterpret_cast<uint16_t *>(&colorP->full), width, height);
#else
  gfx->draw16bitRGBBitmap(area->x1, area->y1, reinterpret_cast<uint16_t *>(&colorP->full), width, height);
#endif
  lv_disp_flush_ready(disp);
}

void lvglTick(void *arg) {
  (void)arg;
  lv_tick_inc(LVGL_TICK_PERIOD_MS);
}

void lvglTouchRead(lv_indev_drv_t *indevDriver, lv_indev_data_t *data) {
  (void)indevDriver;
  data->state = LV_INDEV_STATE_REL;
  if (!touchReady || !touch.isPressed()) {
    return;
  }
  uint8_t points = touch.getPoint(touchX, touchY, touch.getSupportTouchPoint());
  if (points == 0) {
    return;
  }
  data->state = LV_INDEV_STATE_PR;
  data->point.x = touchX[0];
  data->point.y = touchY[0];
}

void updateStatsLabel() {
  if (!statsLabel) {
    return;
  }
  char buf[96];
  snprintf(buf, sizeof(buf), "VIS OK  page=%s  chat=%lu  cards=%lu  settings=%lu",
           pageName(currentPage),
           static_cast<unsigned long>(chatCount),
           static_cast<unsigned long>(cardCount),
           static_cast<unsigned long>(settingCount));
  lv_label_set_text(statsLabel, buf);
}

void updateLvglLabels() {
  if (!lvglReady) {
    return;
  }
  if (titleLabel) {
    lv_label_set_text(titleLabel, "VISUAL AGENT");
  }
  if (chatLogLabel) {
    lv_label_set_text_fmt(chatLogLabel, "Chat bubbles\n%s", lastChat);
  }
  if (agentLabel) {
    lv_label_set_text_fmt(agentLabel, "Agent thought\n%s", agentThought);
  }
  if (cardStatusLabel) {
    lv_label_set_text_fmt(cardStatusLabel, "Card flow\n%s", lastCard);
  }
  if (cardListLabel) {
    lv_label_set_text_fmt(cardListLabel, "cards=%lu\nstream -> review -> done",
                          static_cast<unsigned long>(cardCount));
  }
  if (settingsLabel) {
    lv_label_set_text_fmt(settingsLabel, "Settings\n%s", lastSetting);
  }
  if (settingListLabel) {
    lv_label_set_text_fmt(settingListLabel, "theme=dark\nvoice=serial\nitems=%lu",
                          static_cast<unsigned long>(settingCount));
  }
  updateStatsLabel();
}

void setPage(VisualPage page, const char *source) {
  currentPage = page;
  if (tabview) {
    lv_tabview_set_act(tabview, static_cast<uint32_t>(page), LV_ANIM_OFF);
  }
  updateStatsLabel();
  Serial.print("VIS_PAGE page=");
  Serial.print(pageName(page));
  Serial.print(" source=");
  Serial.println(source);
  Serial.flush();
}

void emitState() {
  Serial.print("VIS_STATE frame=");
  Serial.print(frame);
  Serial.print(" page=");
  Serial.print(pageName(currentPage));
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" lvgl=");
  Serial.print(lvglReady ? 1 : 0);
  Serial.print(" chat=");
  Serial.print(chatCount);
  Serial.print(" cards=");
  Serial.print(cardCount);
  Serial.print(" settings=");
  Serial.print(settingCount);
  Serial.print(" agent=");
  Serial.print(agentEvents);
  Serial.print(" commands=");
  Serial.println(commandCount);
  Serial.flush();
}

void emitCaps() {
  Serial.print("VIS_CAPS lvgl=");
  Serial.print(lv_version_major());
  Serial.print(".");
  Serial.print(lv_version_minor());
  Serial.print(".");
  Serial.print(lv_version_patch());
  Serial.println(" widgets=tabview,labels,cards,settings pages=CHAT,CARDS,SETTINGS");
  Serial.flush();
}

lv_obj_t *makePanel(lv_obj_t *parent, const char *title, lv_coord_t y, lv_coord_t height) {
  lv_obj_t *panel = lv_obj_create(parent);
  lv_obj_set_size(panel, 406, height);
  lv_obj_align(panel, LV_ALIGN_TOP_MID, 0, y);
  lv_obj_set_style_radius(panel, 8, 0);
  lv_obj_set_style_pad_all(panel, 14, 0);
  lv_obj_t *label = lv_label_create(panel);
  lv_label_set_text(label, title);
  lv_obj_set_style_text_font(label, &lv_font_montserrat_18, 0);
  lv_obj_align(label, LV_ALIGN_TOP_LEFT, 0, 0);
  return panel;
}

void createUi() {
  tabview = lv_tabview_create(lv_scr_act(), LV_DIR_TOP, 52);
  lv_obj_set_style_bg_color(tabview, lv_color_hex(0x111827), 0);
  chatTab = lv_tabview_add_tab(tabview, "Chat");
  cardsTab = lv_tabview_add_tab(tabview, "Cards");
  settingsTab = lv_tabview_add_tab(tabview, "Settings");

  lv_obj_t *chatPanel = makePanel(chatTab, "VIS OK", 12, 164);
  titleLabel = lv_label_create(chatPanel);
  lv_label_set_text(titleLabel, "VISUAL AGENT");
  lv_obj_set_style_text_font(titleLabel, &lv_font_montserrat_24, 0);
  lv_obj_align(titleLabel, LV_ALIGN_TOP_LEFT, 0, 34);
  chatLogLabel = lv_label_create(chatPanel);
  lv_label_set_long_mode(chatLogLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(chatLogLabel, 360);
  lv_obj_align(chatLogLabel, LV_ALIGN_TOP_LEFT, 0, 78);

  lv_obj_t *agentPanel = makePanel(chatTab, "Agent", 196, 158);
  agentLabel = lv_label_create(agentPanel);
  lv_label_set_long_mode(agentLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(agentLabel, 360);
  lv_obj_align(agentLabel, LV_ALIGN_TOP_LEFT, 0, 40);

  lv_obj_t *cardPanel = makePanel(cardsTab, "Cards", 20, 180);
  cardStatusLabel = lv_label_create(cardPanel);
  lv_label_set_long_mode(cardStatusLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(cardStatusLabel, 360);
  lv_obj_align(cardStatusLabel, LV_ALIGN_TOP_LEFT, 0, 42);
  cardListLabel = lv_label_create(cardsTab);
  lv_label_set_long_mode(cardListLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(cardListLabel, 380);
  lv_obj_align(cardListLabel, LV_ALIGN_TOP_MID, 0, 230);

  lv_obj_t *settingPanel = makePanel(settingsTab, "Settings", 20, 180);
  settingsLabel = lv_label_create(settingPanel);
  lv_label_set_long_mode(settingsLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(settingsLabel, 360);
  lv_obj_align(settingsLabel, LV_ALIGN_TOP_LEFT, 0, 42);
  settingListLabel = lv_label_create(settingsTab);
  lv_label_set_long_mode(settingListLabel, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(settingListLabel, 380);
  lv_obj_align(settingListLabel, LV_ALIGN_TOP_MID, 0, 230);

  statsLabel = lv_label_create(lv_layer_top());
  lv_obj_set_style_bg_opa(statsLabel, LV_OPA_COVER, 0);
  lv_obj_set_style_bg_color(statsLabel, lv_color_hex(0x0f172a), 0);
  lv_obj_set_style_text_color(statsLabel, lv_color_hex(0xffffff), 0);
  lv_obj_set_style_pad_all(statsLabel, 6, 0);
  lv_obj_align(statsLabel, LV_ALIGN_BOTTOM_MID, 0, -6);
  updateLvglLabels();
}

bool setupLvgl() {
  screenWidth = gfx->width();
  screenHeight = gfx->height();
  size_t pixelCount = static_cast<size_t>(screenWidth) * static_cast<size_t>(screenHeight) / 6;
  lvBuf1 = static_cast<lv_color_t *>(heap_caps_malloc(pixelCount * sizeof(lv_color_t), MALLOC_CAP_DMA));
  lvBuf2 = static_cast<lv_color_t *>(heap_caps_malloc(pixelCount * sizeof(lv_color_t), MALLOC_CAP_DMA));
  if (!lvBuf1 || !lvBuf2) {
    Serial.println("VIS_LVGL_BUFFER_FAILED");
    Serial.flush();
    return false;
  }

  lv_init();
  lv_disp_draw_buf_init(&drawBuf, lvBuf1, lvBuf2, pixelCount);

  static lv_disp_drv_t dispDrv;
  lv_disp_drv_init(&dispDrv);
  dispDrv.hor_res = screenWidth;
  dispDrv.ver_res = screenHeight;
  dispDrv.flush_cb = lvglFlush;
  dispDrv.rounder_cb = lvglRounderCb;
  dispDrv.draw_buf = &drawBuf;
  dispDrv.sw_rotate = 1;
  lv_disp_drv_register(&dispDrv);

  static lv_indev_drv_t indevDrv;
  lv_indev_drv_init(&indevDrv);
  indevDrv.type = LV_INDEV_TYPE_POINTER;
  indevDrv.read_cb = lvglTouchRead;
  lv_indev_drv_register(&indevDrv);

  const esp_timer_create_args_t tickArgs = {
    .callback = &lvglTick,
    .name = "lvgl_tick"
  };
  esp_timer_handle_t tickTimer = nullptr;
  esp_timer_create(&tickArgs, &tickTimer);
  esp_timer_start_periodic(tickTimer, LVGL_TICK_PERIOD_MS * 1000);

  lvglReady = true;
  createUi();
  updateLvglLabels();
  return true;
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("VIS_DISPLAY_FAILED");
    Serial.flush();
    return;
  }
  gfx->setRotation(DISPLAY_ROTATION);
  gfx->setBrightness(200);
  displayReady = true;
}

void setupTouch() {
  touch.setPins(TP_RST, TP_INT);
  touchReady = touch.begin(Wire, CST92XX_SLAVE_ADDRESS, IIC_SDA, IIC_SCL);
  if (!touchReady) {
    Serial.println("VIS_TOUCH_FAILED");
    Serial.flush();
    return;
  }
  touch.setMaxCoordinates(LCD_WIDTH, LCD_HEIGHT);
  touch.setSwapXY(true);
  touch.setMirrorXY(false, true);
  Serial.print("VIS_TOUCH model=");
  Serial.println(touch.getModelName());
  Serial.flush();
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
    VisualPage page;
    String name = upper.substring(5);
    if (parsePage(name, page)) {
      setPage(page, "serial");
    } else {
      Serial.print("VIS_BAD_PAGE value=");
      Serial.println(name);
      Serial.flush();
    }
    return;
  }
  if (upper.startsWith("CHAT:")) {
    chatCount++;
    copyString(lastChat, sizeof(lastChat), command.substring(5));
    setPage(PAGE_CHAT, "serial");
    updateLvglLabels();
    Serial.print("VIS_CHAT count=");
    Serial.print(chatCount);
    Serial.print(" text=");
    Serial.println(lastChat);
    Serial.flush();
    return;
  }
  if (upper.startsWith("AGENT:THINK:")) {
    agentEvents++;
    copyString(agentThought, sizeof(agentThought), command.substring(12));
    setPage(PAGE_CHAT, "serial");
    updateLvglLabels();
    Serial.print("VIS_AGENT event=think count=");
    Serial.print(agentEvents);
    Serial.print(" text=");
    Serial.println(agentThought);
    Serial.flush();
    return;
  }
  if (upper.startsWith("CARD:")) {
    cardCount++;
    copyString(lastCard, sizeof(lastCard), command.substring(5));
    setPage(PAGE_CARDS, "serial");
    updateLvglLabels();
    Serial.print("VIS_CARD count=");
    Serial.print(cardCount);
    Serial.print(" value=");
    Serial.println(lastCard);
    Serial.flush();
    return;
  }
  if (upper.startsWith("SETTING:")) {
    settingCount++;
    copyString(lastSetting, sizeof(lastSetting), command.substring(8));
    setPage(PAGE_SETTINGS, "serial");
    updateLvglLabels();
    Serial.print("VIS_SETTING count=");
    Serial.print(settingCount);
    Serial.print(" value=");
    Serial.println(lastSetting);
    Serial.flush();
    return;
  }

  Serial.print("VIS_UNKNOWN_COMMAND value=");
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
    if (serialBuffer.length() < 180) {
      serialBuffer += ch;
    } else {
      serialBuffer = "";
      Serial.println("VIS_COMMAND_TOO_LONG");
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

  Serial.println("lvgl_visual_agent boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupTouch();
  if (displayReady) {
    setupLvgl();
  }
  emitCaps();
  Serial.print((displayReady && touchReady && lvglReady) ? "VIS_READY" : "VIS_PARTIAL");
  Serial.print(" display=");
  Serial.print(displayReady ? 1 : 0);
  Serial.print(" touch=");
  Serial.print(touchReady ? 1 : 0);
  Serial.print(" lvgl=");
  Serial.println(lvglReady ? 1 : 0);
  Serial.flush();
  emitState();
}

void loop() {
  readSerialCommands();
  if (lvglReady) {
    lv_timer_handler();
  }
  if ((frame % 50) == 0) {
    emitState();
  }
  frame++;
  delay(5);
}
