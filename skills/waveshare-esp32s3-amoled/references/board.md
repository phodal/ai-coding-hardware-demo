# Waveshare ESP32-S3 Touch AMOLED Arduino Notes

## Sources

- Product/docs: https://docs.waveshare.net/ESP32-S3-Touch-AMOLED-1.75C/
- Arduino setup: https://docs.waveshare.net/ESP32-S3-Touch-AMOLED-1.75C/Development-Environment-Setup-Arduino/
- Vendor repo: https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.75C

## Hardware Facts

- MCU: ESP32-S3R8, dual-core Xtensa LX7, 240 MHz.
- PSRAM: 8 MB.
- Display: 1.75 inch AMOLED, 466 x 466.
- Display driver: CO5300 over QSPI.
- Touch: CST9217 over I2C.
- PMU: AXP2101.
- IMU: QMI8658.
- USB: native Type-C serial/JTAG path.

## Arduino Dependencies

Use the vendor `examples/Arduino-v3.3.5/libraries` folder. Key libraries:

- `GFX_Library_for_Arduino` v1.6.4
- `SensorLib` v0.3.3
- `XPowersLib` v0.2.6
- `lvgl` v8.4.0
- `Mylibrary` for board pin macros
- root `lv_conf.h` for LVGL examples

For basic display smoke tests, `GFX_Library_for_Arduino`, `Wire`, and 1.75C `pin_config.h` are enough.

## Baseline Board Options

There is no dedicated `ESP32-S3-Touch-AMOLED-1.75C` FQBN in the observed `esp32:esp32` 3.3.5 or 3.3.10 package. Use:

```text
esp32:esp32:esp32s3:USBMode=hwcdc,UploadMode=default,CDCOnBoot=cdc,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,UploadSpeed=921600
```

If a future core adds a 1.75C FQBN, inspect `arduino-cli board details --fqbn <new-fqbn>` before switching. Keep `pin_config.h` aligned with the 1.75C vendor example.

## Known Failure Modes

- `esp32:esp32@3.3.10` plus the vendor `Arduino-v3.3.5` GFX library can fail on `spiFrequencyToClockDiv` signature changes. Install `esp32:esp32@3.3.5`.
- Running multiple `arduino-cli compile` processes at once can corrupt or truncate shared cache artifacts. Use `--jobs 1` and dedicated `--build-path`.
- Arduino IDE may show nearby Waveshare board profiles like 1.43, 1.64, or 1.8. Do not assume they are correct for 1.75C display/touch behavior.
- For serial validation on macOS, raw `stty` + `cat` can be more reliable than `arduino-cli monitor` on the USB Serial/JTAG port. If `arduino-cli monitor` creates a 0-byte log but raw `cat /dev/cu.usbmodem*` receives frames, treat raw serial as the validation path.
- For visual validation, display a static high-contrast screen with large OCR-friendly text before using a camera. Avoid animated/random drawing for acceptance tests because it can look like display corruption.
- If upload is unreliable at 921600 baud, retry with `UploadSpeed=460800`.
