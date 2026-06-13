#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include <driver/i2s.h>
#include <esp_vad.h>
#include "es7210.h"
#include "pin_config.h"

#define VAD_SAMPLE_RATE_HZ 16000
#define VAD_FRAME_LENGTH_MS 30
#define VAD_BUFFER_LENGTH (VAD_FRAME_LENGTH_MS * VAD_SAMPLE_RATE_HZ / 1000)
#define I2S_CH I2S_NUM_1

#ifndef DISPLAY_ROTATION
#define DISPLAY_ROTATION 0
#endif

Arduino_DataBus *bus = new Arduino_ESP32QSPI(
  LCD_CS, LCD_SCLK, LCD_SDIO0, LCD_SDIO1, LCD_SDIO2, LCD_SDIO3);

Arduino_CO5300 *gfx = new Arduino_CO5300(
  bus, LCD_RESET, 0, LCD_WIDTH, LCD_HEIGHT, 6, 0, 0, 0);

int16_t *vadBuffer = nullptr;
vad_handle_t vadHandle = nullptr;
size_t bytesRead = 0;
uint32_t frame = 0;
uint32_t speechCount = 0;
uint32_t signalCount = 0;
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

void drawAudioScreen(const char *status, uint32_t rms, uint32_t peak) {
  if (!displayReady) {
    return;
  }

  gfx->fillScreen(RGB565_BLACK);
  gfx->drawRect(8, 8, LCD_WIDTH - 16, LCD_HEIGHT - 16, RGB565_GREEN);
  centerText("MIC", 54, 6, RGB565_CYAN);
  centerText(status, 150, 7, RGB565_WHITE);

  gfx->setTextSize(2);
  gfx->setTextColor(RGB565_YELLOW, RGB565_BLACK);
  gfx->setCursor(42, 310);
  gfx->print("rms=");
  gfx->print(rms);
  gfx->setCursor(42, 342);
  gfx->print("peak=");
  gfx->print(peak);
}

void setupDisplay() {
  if (!gfx->begin()) {
    Serial.println("audio_vad_probe gfx begin failed");
    Serial.flush();
    return;
  }

  gfx->setBrightness(200);
  gfx->setRotation(DISPLAY_ROTATION);
  displayReady = true;
  drawAudioScreen("READY", 0, 0);
}

void setupAudio() {
  audio_hal_codec_config_t cfg = {
    .adc_input = AUDIO_HAL_ADC_INPUT_ALL,
    .codec_mode = AUDIO_HAL_CODEC_MODE_ENCODE,
    .i2s_iface = {
      .mode = AUDIO_HAL_MODE_SLAVE,
      .fmt = AUDIO_HAL_I2S_NORMAL,
      .samples = AUDIO_HAL_16K_SAMPLES,
      .bits = AUDIO_HAL_BIT_LENGTH_16BITS,
    },
  };

  uint32_t retVal = ESP_OK;
  retVal |= es7210_adc_init(&Wire, &cfg);
  retVal |= es7210_adc_config_i2s(cfg.codec_mode, &cfg.i2s_iface);
  retVal |= es7210_adc_set_gain(
    (es7210_input_mics_t)(ES7210_INPUT_MIC1 | ES7210_INPUT_MIC2),
    (es7210_gain_value_t)GAIN_0DB);
  retVal |= es7210_adc_set_gain(
    (es7210_input_mics_t)(ES7210_INPUT_MIC3 | ES7210_INPUT_MIC4),
    (es7210_gain_value_t)GAIN_37_5DB);
  retVal |= es7210_adc_ctrl_state(cfg.codec_mode, AUDIO_HAL_CTRL_START);

  Serial.print("audio_vad_probe codec_ret=");
  Serial.println(retVal);

  i2s_config_t i2sConfig = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = VAD_SAMPLE_RATE_HZ,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ALL_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 8,
    .dma_buf_len = 64,
    .use_apll = false,
    .tx_desc_auto_clear = true,
    .fixed_mclk = 0,
    .mclk_multiple = I2S_MCLK_MULTIPLE_256,
    .bits_per_chan = I2S_BITS_PER_CHAN_16BIT,
    .chan_mask = (i2s_channel_t)(I2S_TDM_ACTIVE_CH0 | I2S_TDM_ACTIVE_CH1),
  };

  i2s_pin_config_t pinConfig = {0};
  pinConfig.bck_io_num = PIN_ES7210_BCLK;
  pinConfig.ws_io_num = PIN_ES7210_LRCK;
  pinConfig.data_in_num = PIN_ES7210_DIN;
  pinConfig.mck_io_num = PIN_ES7210_MCLK;

  ESP_ERROR_CHECK(i2s_driver_install(I2S_CH, &i2sConfig, 0, NULL));
  ESP_ERROR_CHECK(i2s_set_pin(I2S_CH, &pinConfig));
  ESP_ERROR_CHECK(i2s_zero_dma_buffer(I2S_CH));

  vadHandle = vad_create(VAD_MODE_0);
  vadBuffer = (int16_t *)malloc(VAD_BUFFER_LENGTH * sizeof(int16_t));
  if (vadBuffer == nullptr) {
    Serial.println("audio_vad_probe malloc failed");
    Serial.flush();
  }
}

void setup() {
  Serial.begin(115200);
  uint32_t serialWaitStart = millis();
  while (!Serial && (millis() - serialWaitStart < 5000)) {
    delay(100);
  }

  Serial.println("audio_vad_probe boot");
  Serial.print("psram_kb=");
  Serial.println(ESP.getPsramSize() / 1024);
  Serial.flush();

  Wire.begin(IIC_SDA, IIC_SCL);
  setupDisplay();
  setupAudio();

  Serial.println("AUDIO_VAD_READY");
  Serial.flush();
}

void loop() {
  if (vadBuffer == nullptr || vadHandle == nullptr) {
    delay(1000);
    return;
  }

  i2s_read(I2S_CH, (char *)vadBuffer, VAD_BUFFER_LENGTH * sizeof(int16_t), &bytesRead, portMAX_DELAY);

  uint32_t sumAbs = 0;
  uint32_t peak = 0;
  size_t samples = bytesRead / sizeof(int16_t);
  for (size_t i = 0; i < samples; i++) {
    uint32_t value = abs((int)vadBuffer[i]);
    sumAbs += value;
    if (value > peak) {
      peak = value;
    }
  }

  uint32_t rmsProxy = samples > 0 ? sumAbs / samples : 0;
  vad_state_t vadState = vad_process(vadHandle, vadBuffer, VAD_SAMPLE_RATE_HZ, VAD_FRAME_LENGTH_MS);
  bool speech = vadState == VAD_SPEECH;
  bool signal = rmsProxy >= 5 && peak >= 20;
  if (signal) {
    signalCount++;
    Serial.print("AUDIO_SIGNAL_DETECTED frame=");
    Serial.print(frame);
    Serial.print(" rms=");
    Serial.print(rmsProxy);
    Serial.print(" peak=");
    Serial.println(peak);
  }

  if (speech) {
    speechCount++;
    Serial.print("AUDIO_SPEECH_DETECTED frame=");
    Serial.print(frame);
    Serial.print(" rms=");
    Serial.print(rmsProxy);
    Serial.print(" peak=");
    Serial.println(peak);
  }

  if ((frame % 10) == 0) {
    Serial.print("AUDIO_METRIC frame=");
    Serial.print(frame);
    Serial.print(" bytes=");
    Serial.print(bytesRead);
    Serial.print(" rms=");
    Serial.print(rmsProxy);
    Serial.print(" peak=");
    Serial.print(peak);
    Serial.print(" speech=");
    Serial.print(speech ? 1 : 0);
    Serial.print(" speech_count=");
    Serial.print(speechCount);
    Serial.print(" signal_count=");
    Serial.println(signalCount);
    if ((frame % 100) == 0) {
      Serial.println("AUDIO_VAD_READY");
    }
    Serial.flush();
  }

  if ((frame % 20) == 0) {
    drawAudioScreen((speechCount > 0 || signalCount > 0) ? "OK" : "LISTEN", rmsProxy, peak);
  }

  frame++;
  delay(5);
}
