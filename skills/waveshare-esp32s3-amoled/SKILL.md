---
name: waveshare-esp32s3-amoled
description: Build, upload, and debug Arduino CLI projects for Waveshare ESP32-S3 Touch AMOLED boards, especially ESP32-S3-Touch-AMOLED-1.75C on macOS. Use when setting up arduino-cli, installing the Espressif esp32 core, compiling Waveshare Arduino-v3.3.5 examples, choosing the correct ESP32-S3 FQBN/options, detecting /dev/cu.usbmodem serial ports, flashing sketches, or validating hardware bring-up through serial monitor output.
---

# Waveshare ESP32-S3 AMOLED

## Overview

Use this skill to bring up Waveshare ESP32-S3 Touch AMOLED Arduino projects through `arduino-cli`, with reproducible CLI setup, vendor library handling, compile/upload commands, and serial validation.

## Default Workflow

1. Inspect the hardware and local state:
   - Run `arduino-cli version`, `arduino-cli core list`, and `arduino-cli board list`.
   - Prefer `/dev/cu.usbmodem*` on macOS; the known local port has been `/dev/cu.usbmodem83101`.
   - Search installed boards with `arduino-cli board listall | rg -i 'waveshare|amoled|esp32.?s3|touch'`.

2. Align versions before debugging code:
   - Use `esp32:esp32@3.3.5` for Waveshare `examples/Arduino-v3.3.5`.
   - If `esp32:esp32@3.3.10` is installed, expect the bundled GFX v1.6.4 library to fail around `spiFrequencyToClockDiv`; install 3.3.5 instead.
   - Add the Espressif package URL if missing: `https://espressif.github.io/arduino-esp32/package_esp32_index.json`.

3. Use the correct build surface:
   - Vendor repo: `waveshareteam/ESP32-S3-Touch-AMOLED-1.75C`.
   - Arduino examples/libraries: `examples/Arduino-v3.3.5`.
   - The current Espressif core exposes Waveshare AMOLED 1.43/1.64/1.8/1.91/etc., but not a dedicated 1.75C FQBN. For 1.75C, use generic `esp32:esp32:esp32s3` plus explicit options and the 1.75C `pin_config.h`.

4. Compile serially:
   - Do not run concurrent `arduino-cli compile` jobs into the same cache/build path.
   - Use `--jobs 1`, `--clean`, and a dedicated `--build-path` for reliable validation.

5. Upload and validate:
   - Upload to the detected `/dev/cu.usbmodem*` port.
   - Open `arduino-cli monitor --config baudrate=115200,dtr=on,rts=off`.
   - Treat repeated sketch serial lines plus visible AMOLED output as the baseline pass condition.

## Known 1.75C FQBN

Use this FQBN unless a future Espressif core adds a real 1.75C board profile:

```text
esp32:esp32:esp32s3:USBMode=hwcdc,UploadMode=default,CDCOnBoot=cdc,CPUFreq=240,FlashMode=qio,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,UploadSpeed=921600
```

If upload fails, retry with `UploadSpeed=460800` before changing board families.

## Helper Script

Use `scripts/waveshare-arduino-cli.sh` from this skill for a portable setup/build/upload/monitor wrapper when the target project does not already provide scripts.

Example:

```bash
/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh setup /path/to/project
/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh build /path/to/project
/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh upload /path/to/project
```

If the project contains `scripts/setup.sh`, `scripts/build.sh`, `scripts/upload.sh`, or `scripts/monitor.sh`, prefer those project scripts because they encode project-local sketch paths.

## References

Read `references/board.md` when you need board facts, source links, library names, or troubleshooting notes.
