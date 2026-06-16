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
make xiaozhi-backup
make xiaozhi-runtime-check
make xiaozhi-visual-check
make xiaozhi-runtime-visual-check
make xiaozhi-idf-env
make xiaozhi-idf-build
CONFIRM=--yes make xiaozhi-flash
```

Use `latest`, `inspect`, `preflight`, and `backup` first. They only query/download the release asset, confirm the firmware archive shape, hash `merged-binary.bin`, inspect local source/ESP-IDF readiness, confirm the serial/esptool environment, and read the current board flash to a local backup. `CONFIRM=--yes make xiaozhi-flash` is the first destructive XiaoZhi firmware step.

`make xiaozhi-preflight` prefers live GitHub release metadata, but falls back to an existing matching zip under `.vendor/xiaozhi/firmware` when the release lookup fails. The summary reports `release_source=live` or `release_source=cache`; set `XIAOZHI_RELEASE_CACHE_FALLBACK=0` when a live release lookup is required.

After an approved XiaoZhi flash, run:

```bash
make xiaozhi-runtime-check
make xiaozhi-visual-check
make xiaozhi-runtime-visual-check
```

This resets the ESP32-S3 while serial capture is already open, records `.logs/xiaozhi-runtime-*.log`, and looks for XiaoZhi-specific onboarding or activation markers such as `XiaoZhi`, `小智`, `验证码`, `激活`, or `配网`. It does not flash firmware, open the camera, use the host microphone, or play audio. It emits:

- `xiaozhi_runtime_summary ... destructive=0 audio=0`

`make xiaozhi-visual-check` runs the camera OCR gate only. `make xiaozhi-runtime-visual-check` runs serial first, then camera OCR. The visual gate accepts any marker from `XIAOZHI_VISUAL_EXPECT_ANY` and supports Chinese OCR markers by using raw OCR text when the marker is non-ASCII.

If the upstream firmware changes its boot log wording, override the marker set without weakening the no-audio boundary:

```bash
XIAOZHI_RUNTIME_EXPECT_ANY='XiaoZhi,验证码,配网' make xiaozhi-runtime-check
XIAOZHI_RUNTIME_EXPECT_ALL='XiaoZhi' make xiaozhi-runtime-check
XIAOZHI_VISUAL_EXPECT_ANY='XiaoZhi,验证码,配网' make xiaozhi-visual-check
```

`make xiaozhi-flash` is intentionally guarded. With `CONFIRM=--yes`, it expands to:

```bash
scripts/xiaozhi.sh flash --yes
```

This writes the latest `waveshare-esp32-s3-touch-amoled-1.75c` merged binary to flash address `0x0` using esptool from the installed Arduino ESP32 core when no standalone `esptool` is available.

`make xiaozhi-backup` is read-only and emits:

- `xiaozhi_backup_summary ... path=... bytes=... sha256=... destructive=0 audio=0`

To restore a backup, pass its path explicitly and confirm the destructive write:

```bash
BACKUP=.vendor/xiaozhi/backups/esp32s3-flash-YYYYMMDD-HHMMSS.bin CONFIRM=--yes make xiaozhi-restore
```

`make xiaozhi-preflight` is non-destructive and emits:

- `xiaozhi_firmware_summary ... merged_size=... merged_sha256=...`
- `xiaozhi_preflight_summary ... port=... esptool=... source=... idf=... destructive=0 audio=0`

## Source Route

```bash
make xiaozhi-source-clone
make xiaozhi-source-check
make xiaozhi-idf-env
make xiaozhi-idf-build
scripts/xiaozhi.sh idf-flash
scripts/xiaozhi.sh idf-monitor
```

The source build route uses the local ESP-IDF checkout by default. XiaoZhi source `v2.2.6-37-g3f9e5fc` declares `idf >=5.5.2`, so the local automation defaults to `.vendor/esp-idf-v5.5.4` and `~/.espressif/python_env/idf5.5_py3.14_env`.
`make xiaozhi-idf-env` is non-destructive and emits `xiaozhi_idf_summary ... destructive=0 audio=0`.
The local source-build defaults include `config/xiaozhi-sdkconfig.defaults`, which selects `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C=y`.
`make xiaozhi-idf-build` compiles the source only; it does not flash the board or open audio devices, and it emits `xiaozhi_idf_build_summary ... destructive=0 audio=0` after a successful build.

Useful overrides:

```bash
XIAOZHI_BOARD_SLUG=waveshare-esp32-s3-touch-amoled-1.75c
XIAOZHI_RELEASE_REPO=78/xiaozhi-esp32
XIAOZHI_WORK_DIR=.vendor/xiaozhi
XIAOZHI_FLASH_ADDRESS=0x0
XIAOZHI_FLASH_SIZE=0x1000000
XIAOZHI_BAUD=921600
XIAOZHI_BACKUP_BAUD=115200
XIAOZHI_BACKUP_NO_STUB=1
XIAOZHI_BACKUP_SILENT=1
XIAOZHI_RUNTIME_BAUD=115200
XIAOZHI_RUNTIME_SECONDS=20
XIAOZHI_RUNTIME_PULSE_RTS=1
XIAOZHI_RUNTIME_INPUT_LOG=
XIAOZHI_RUNTIME_EXPECT_ANY='XiaoZhi,Xiaozhi,xiaozhi,小智,验证码,激活,activation,Activation,配网'
XIAOZHI_RUNTIME_EXPECT_ALL=
XIAOZHI_VISUAL_EXPECT_ANY='XiaoZhi,Xiaozhi,xiaozhi,小智,验证码,激活,activation,Activation,配网'
XIAOZHI_SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.esp32s3;/absolute/path/to/config/xiaozhi-sdkconfig.defaults'
XIAOZHI_IDF_PATH=.vendor/esp-idf-v5.5.4
XIAOZHI_IDF_PYTHON_ENV_PATH=~/.espressif/python_env/idf5.5_py3.14_env
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
- Latest `xiaozhi_preflight_summary`: `tag=v2.2.6 asset=v2.2.6_waveshare-esp32-s3-touch-amoled-1.75c.zip asset_size=3116104 release_source=live slug=waveshare-esp32-s3-touch-amoled-1.75c port=/dev/cu.usbmodem83101 esptool=/Users/phodal/Library/Arduino15/packages/esp32/tools/esptool_py/5.1.0/esptool source=v2.2.6-37-g3f9e5fc idf=/Users/phodal/hardware/arduino/.vendor/esp-idf-v5.5.4/tools/idf.py destructive=0 audio=0`.
- `XIAOZHI_RELEASE_REPO=invalid/invalid make xiaozhi-preflight`: passed the non-destructive cache fallback path and reported `release_source=cache`, proving preflight can still validate the locally cached firmware zip during release API/TLS failures.
- Latest `merged-binary.bin` SHA-256: `c08f389e2650b2076d2155fa62c0b34c5f3359e07833a8fca5f0f53c6e8bf7dd`.
- `make xiaozhi-backup`: read the current board flash without writing or using audio hardware, preserving a rollback image before any approved XiaoZhi flash.
- Latest `xiaozhi_backup_summary`: `path=/Users/phodal/hardware/arduino/.vendor/xiaozhi/backups/esp32s3-flash-20260616-230250.bin address=0x0 size=0x1000000 baud=115200 no_stub=1 bytes=16777216 sha256=cdb840d88574aed6196f070d085dd3363d813f3b55847ac4a5b6ac20b328262a destructive=0 audio=0`.
- `make xiaozhi-runtime-check`, `make xiaozhi-visual-check`, and `make xiaozhi-runtime-visual-check` are wired for the post-flash no-audio runtime gate, but they have not been run against XiaoZhi firmware yet because flashing was not approved during this update.
- Offline checker validation used a fixture log with `XiaoZhi`/`验证码` markers and emitted `xiaozhi_runtime_summary ... destructive=0 audio=0`; `XIAOZHI_RUNTIME_INPUT_LOG=<path> make xiaozhi-runtime-check` provides the same no-serial fixture path for Skill/helper smoke tests.
- Camera OCR matcher validation used an existing captured image with `OCR_EXPECTED_ANY=OK`, proving the multi-marker path without recapturing or using audio devices.
- Standalone `esptool.py` is not installed, but Arduino ESP32 core provides `~/Library/Arduino15/packages/esp32/tools/esptool_py/5.1.0/esptool`.
- `make xiaozhi-source-clone` cloned official source to `.vendor/xiaozhi/source` at `v2.2.6-37-g3f9e5fc`.
- `make xiaozhi-source-check` confirmed the source tree contains `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C`.
- `make xiaozhi-idf-env` on 2026-06-14 activated ESP-IDF `v5.5.4` from `.vendor/esp-idf-v5.5.4` with Python env `~/.espressif/python_env/idf5.5_py3.14_env`.
- `make xiaozhi-idf-build` on 2026-06-14 compiled the official XiaoZhi source without flashing firmware or using audio hardware.
- Latest `xiaozhi_idf_build_summary`: `idf=ESP-IDF_v5.5.4 app_bin=/Users/phodal/hardware/arduino/.vendor/xiaozhi/source/build/xiaozhi.bin app_size=2944176 bootloader_size=16256 partition_size=3072 assets_size=2851677 destructive=0 audio=0`.
- Earlier ESP-IDF `v5.4.4` was rejected by the XiaoZhi component solver because `main/idf_component.yml` requires `idf >=5.5.2`.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino idf-build`: passed through the repo Skill helper.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino idf-build`: passed through the global Skill helper.
- Flashing was not run during this documentation update.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target xiaozhi-ai --allow-external --per-target-timeout 180 --max-failures 1"`: ran the non-destructive `xiaozhi-preflight` suite target without flashing firmware or using audio hardware.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-071849/summary.json`.
- Latest suite target log: `.logs/hardware-smoke-suite/20260614-071849/xiaozhi-ai.log`.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino preflight`: passed through the repo Skill helper.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh xiaozhi /Users/phodal/hardware/arduino preflight`: passed through the global Skill helper.
