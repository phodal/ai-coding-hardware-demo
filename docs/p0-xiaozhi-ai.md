# P0 XiaoZhi AI Bring-up

This lane covers the two Waveshare-documented XiaoZhi AI paths for the ESP32-S3-Touch-AMOLED-1.75C:

- no-development-environment flashing from a prebuilt firmware zip
- ESP-IDF source checkout/build/flash

The prebuilt firmware route is the first acceptance gate because it proves the board can boot the XiaoZhi voice assistant before we start modifying source.

## Commands

```bash
make xiaozhi-latest
make xiaozhi-download
make xiaozhi-inspect
make xiaozhi-preflight
CONFIRM=--yes make xiaozhi-flash
```

Use `latest`, `inspect`, and `preflight` first. They only query/download the release asset, confirm the firmware archive shape, hash `merged-binary.bin`, inspect local source/ESP-IDF readiness, and confirm the serial/esptool environment. `CONFIRM=--yes make xiaozhi-flash` is the first destructive step.

`make xiaozhi-flash` is intentionally guarded. With `CONFIRM=--yes`, it expands to:

```bash
scripts/xiaozhi.sh flash --yes
```

This writes the latest `waveshare-esp32-s3-touch-amoled-1.75c` merged binary to flash address `0x0` using esptool from the installed Arduino ESP32 core when no standalone `esptool` is available.

`make xiaozhi-preflight` is non-destructive and emits:

- `xiaozhi_firmware_summary ... merged_size=... merged_sha256=...`
- `xiaozhi_preflight_summary ... port=... esptool=... source=... idf=... destructive=0 audio=0`

## Source Route

```bash
make xiaozhi-source-clone
make xiaozhi-source-check
scripts/xiaozhi.sh idf-build
scripts/xiaozhi.sh idf-flash
scripts/xiaozhi.sh idf-monitor
```

The source build route requires an ESP-IDF shell where `idf.py` is available. The script checks for `idf.py` and fails early when ESP-IDF is not sourced.
The local source-build defaults include `config/xiaozhi-sdkconfig.defaults`, which selects `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C=y`.

Useful overrides:

```bash
XIAOZHI_BOARD_SLUG=waveshare-esp32-s3-touch-amoled-1.75c
XIAOZHI_RELEASE_REPO=78/xiaozhi-esp32
XIAOZHI_WORK_DIR=.vendor/xiaozhi
XIAOZHI_FLASH_ADDRESS=0x0
XIAOZHI_BAUD=921600
XIAOZHI_SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.esp32s3;/absolute/path/to/config/xiaozhi-sdkconfig.defaults'
```

## Device Onboarding After Flash

After flashing, XiaoZhi starts its own Wi-Fi onboarding flow:

1. Connect to the device AP named like `Xiaozhi-xxxxxx`.
2. Open `http://192.168.4.1` if the captive portal does not open automatically.
3. Connect it to a 2.4 GHz Wi-Fi network.
4. Add the spoken/displayed 6-digit code in the XiaoZhi control panel.
5. Wake it with `你好，小智`.

Flashing XiaoZhi replaces the Arduino demo currently on the board. To return to local demos, run one of the existing Arduino upload/smoke commands again.

## Verified Locally

- `make xiaozhi-latest` on 2026-06-13 detected release `v2.2.6`.
- Matched asset: `v2.2.6_waveshare-esp32-s3-touch-amoled-1.75c.zip`.
- `make xiaozhi-inspect` confirmed the downloaded asset contains `merged-binary.bin` with size `11240285` bytes.
- `make xiaozhi-preflight` verifies the current release asset, `merged-binary.bin` SHA-256, esptool path, serial port, source checkout marker, and ESP-IDF availability without flashing firmware or using audio hardware.
- Latest `xiaozhi_preflight_summary`: `tag=v2.2.6 asset=v2.2.6_waveshare-esp32-s3-touch-amoled-1.75c.zip asset_size=3116104 slug=waveshare-esp32-s3-touch-amoled-1.75c port=/dev/cu.usbmodem83101 esptool=/Users/phodal/Library/Arduino15/packages/esp32/tools/esptool_py/5.1.0/esptool source=v2.2.6-37-g3f9e5fc idf=missing destructive=0 audio=0`.
- Latest `merged-binary.bin` SHA-256: `c08f389e2650b2076d2155fa62c0b34c5f3359e07833a8fca5f0f53c6e8bf7dd`.
- Standalone `esptool.py` is not installed, but Arduino ESP32 core provides `~/Library/Arduino15/packages/esp32/tools/esptool_py/5.1.0/esptool`.
- `make xiaozhi-source-clone` cloned official source to `.vendor/xiaozhi/source` at `v2.2.6-37-g3f9e5fc`.
- `make xiaozhi-source-check` confirmed the source tree contains `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C`.
- `scripts/xiaozhi.sh idf-build` currently fails early because `idf.py` is not available in this shell; source compilation is gated on installing/sourcing ESP-IDF.
- Flashing was not run during this documentation update.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target xiaozhi-ai --allow-external --per-target-timeout 180 --max-failures 1"`: ran the non-destructive `xiaozhi-preflight` suite target without flashing firmware or using audio hardware.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-062838/summary.json`.
- Latest suite target log: `.logs/hardware-smoke-suite/20260614-062838/xiaozhi-ai.log`.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino preflight`: passed through the repo Skill helper.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino preflight`: passed through the global Skill helper.
