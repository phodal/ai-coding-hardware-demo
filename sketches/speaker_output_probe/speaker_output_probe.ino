#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <ESP_I2S.h>
#include <Wire.h>
#include <math.h>
#include "esp_check.h"
#include "es8311.h"
#include "pin_config.h"

#define SPEAKER_SAMPLE_RATE 16000
#define SPEAKER_VOLUME 95
#define SPEAKER_MIC_GAIN (es8311_mic_gain_t)(3)
#define I2C_NUM 0
#define TONE_BUFFER_FRAMES 128

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

#ifndef PI
#define PI 3.14159265358979323846
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

I2SClass i2s;
bool displayReady = false;
bool audioReady = false;
uint32_t playCount = 0;
const char *TAG = "speaker_output_probe";

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

void drawSpeakerScreen(const char *status, uint16_t color) {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, color);
  centerText("SPK", 58, 7, RGB565_CYAN);
  centerText(status, 168, 8, RGB565_WHITE);
  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  gfx->setCursor(72, 338);
  gfx->print("tone output");
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("speaker_output_probe gfx begin failed");
    Serial.flush();
    return;
  }

  gfx->setBrightness(200);
  gfx->setRotation(DISPLAY_ROTATION);
  displayReady = true;
  drawSpeakerScreen("READY", RGB565_BLUE);
}

esp_err_t es8311CodecInit() {
  es8311_handle_t esHandle = es8311_create(I2C_NUM, ES8311_ADDRRES_0);
  ESP_RETURN_ON_FALSE(esHandle, ESP_FAIL, TAG, "es8311 create failed");
  const es8311_clock_config_t esClock = {
    .mclk_inverted = false,
    .sclk_inverted = false,
    .mclk_from_mclk_pin = true,
    .mclk_frequency = SPEAKER_SAMPLE_RATE * 256,
    .sample_frequency = SPEAKER_SAMPLE_RATE,
  };

  ESP_RETURN_ON_ERROR(
    es8311_init(esHandle, &esClock, ES8311_RESOLUTION_16, ES8311_RESOLUTION_16),
    TAG,
    "es8311 init failed");
  ESP_RETURN_ON_ERROR(
    es8311_sample_frequency_config(esHandle, esClock.mclk_frequency, esClock.sample_frequency),
    TAG,
    "es8311 sample frequency failed");
  ESP_RETURN_ON_ERROR(es8311_microphone_config(esHandle, false), TAG, "es8311 mic config failed");
  ESP_RETURN_ON_ERROR(es8311_voice_volume_set(esHandle, SPEAKER_VOLUME, NULL), TAG, "es8311 volume failed");
  ESP_RETURN_ON_ERROR(es8311_microphone_gain_set(esHandle, SPEAKER_MIC_GAIN), TAG, "es8311 mic gain failed");
  return ESP_OK;
}

void setupAudio() {
  i2s.setPins(PIN_ES7210_BCLK, PIN_ES7210_LRCK, PIN_ES8311_DOUT, PIN_ES7210_DIN, PIN_ES7210_MCLK);
  if (!i2s.begin(I2S_MODE_STD, SPEAKER_SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO, I2S_STD_SLOT_BOTH)) {
    Serial.println("speaker_output_probe i2s begin failed");
    Serial.flush();
    return;
  }

  pinMode(PA, OUTPUT);
  digitalWrite(PA, HIGH);

  esp_err_t ret = es8311CodecInit();
  Serial.print("speaker_output_probe codec_ret=");
  Serial.println((int)ret);
  audioReady = (ret == ESP_OK);
}

void writeTone(float frequency, uint32_t durationMs, int16_t amplitude) {
  int16_t samples[TONE_BUFFER_FRAMES * 2];
  const uint32_t totalFrames = (SPEAKER_SAMPLE_RATE * durationMs) / 1000;
  float phase = 0.0f;
  const float phaseStep = 2.0f * (float)PI * frequency / (float)SPEAKER_SAMPLE_RATE;
  uint32_t framesWritten = 0;

  while (framesWritten < totalFrames) {
    uint32_t frames = min((uint32_t)TONE_BUFFER_FRAMES, totalFrames - framesWritten);
    for (uint32_t i = 0; i < frames; i++) {
      int16_t sample = (int16_t)(sinf(phase) * amplitude);
      samples[i * 2] = sample;
      samples[i * 2 + 1] = sample;
      phase += phaseStep;
      if (phase > 2.0f * (float)PI) {
        phase -= 2.0f * (float)PI;
      }
    }
    i2s.write((uint8_t *)samples, frames * 2 * sizeof(int16_t));
    framesWritten += frames;
  }
}

void playProbeTone() {
  if (!audioReady) {
    Serial.println("SPEAKER_TONE_FAILED audio_not_ready");
    Serial.flush();
    drawSpeakerScreen("FAIL", RGB565_RED);
    return;
  }

  playCount++;
  drawSpeakerScreen("PLAY", RGB565_GREEN);
  Serial.print("SPEAKER_TONE_START count=");
  Serial.print(playCount);
  Serial.println(" tones=1000,1500");
  Serial.flush();

  writeTone(1000.0f, 1800, 12000);
  delay(180);
  writeTone(1500.0f, 1800, 12000);

  Serial.print("SPEAKER_TONE_END count=");
  Serial.println(playCount);
  Serial.flush();
  drawSpeakerScreen("OK", RGB565_GREEN);
}

void handleCommand(String command) {
  command.trim();
  command.toUpperCase();
  if (command.length() == 0) {
    return;
  }

  if (command == "PING") {
    Serial.println("PONG");
  } else if (command == "PLAY") {
    playProbeTone();
  } else if (command == "STATUS") {
    Serial.print("SPEAKER_OUTPUT_STATUS audio=");
    Serial.print(audioReady ? "ready" : "failed");
    Serial.print(" plays=");
    Serial.println(playCount);
  } else {
    Serial.print("UNKNOWN_COMMAND:");
    Serial.println(command);
  }
  Serial.flush();
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("speaker_output_probe boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupAudio();

  Serial.println(audioReady ? "SPEAKER_OUTPUT_READY" : "SPEAKER_OUTPUT_FAILED");
  Serial.flush();
}

void loop() {
  if (Serial.available()) {
    handleCommand(Serial.readStringUntil('\n'));
  }

  static uint32_t lastHeartbeat = 0;
  if (millis() - lastHeartbeat > 2000) {
    lastHeartbeat = millis();
    Serial.print("SPEAKER_OUTPUT_HEARTBEAT audio=");
    Serial.print(audioReady ? "ready" : "failed");
    Serial.print(" plays=");
    Serial.println(playCount);
    Serial.flush();
  }
  delay(10);
}
