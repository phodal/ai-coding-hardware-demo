# Waveshare ESP32-S3 Touch AMOLED 1.75C Arduino CLI

This workspace automates build, upload, and serial monitoring for the Waveshare ESP32-S3-Touch-AMOLED-1.75C using `arduino-cli`.

## Current Tested Baseline

- `arduino-cli` 1.5.1
- `esp32:esp32` core 3.3.5
- Port: `/dev/cu.usbmodem83101`
- Sketch: `sketches/codex_hello_world`
- Serial diagnostic sketch: `sketches/serial_probe`
- Visual OCR sketch: `sketches/display_ocr_check`
- Vendor examples/libraries: `/Users/phodal/Downloads/ESP32-S3-Touch-AMOLED-1.75C-main/examples/Arduino-v3.3.5`

The installed ESP32 core does not currently expose a dedicated `ESP32-S3-Touch-AMOLED-1.75C` FQBN. The scripts use `esp32:esp32:esp32s3` with explicit board options and the Waveshare 1.75C `pin_config.h`.

## Commands

```bash
make setup
make build
make upload
make monitor
make smoke
make visual-smoke
make camera-aligner
make official-demos
make official-build DEMO=01-helloworld
make official-smoke DEMO=01-helloworld
```

Override defaults with environment variables or `.env`:

```bash
ARDUINO_PORT=/dev/cu.usbmodem83101 make upload
WAVESHARE_VENDOR_DIR=/path/to/ESP32-S3-Touch-AMOLED-1.75C-main make build
```

`make smoke` builds with a dedicated build directory, uploads, then records a short serial log under `.logs/`.
On this macOS USB Serial/JTAG port, raw `stty` + `cat` captures data reliably; set `ARDUINO_CLI_MONITOR=1` to force `arduino-cli monitor`.

`make visual-smoke` uploads a static high-contrast OCR screen and then captures one camera frame with `ffmpeg` before checking it with macOS Vision OCR. Defaults:

```bash
CAMERA_DEVICE=0
CAMERA_SIZE=1280x720
CAMERA_CROP="iw*0.55:ih*0.65:(iw-ow)/2:(ih-oh)/2"
OCR_ROTATE=0
DISPLAY_ROTATION=0
OCR_EXPECTED="OK"
OCR_ENGINE=vision
```

Point the camera at the AMOLED before running the command. If macOS asks for camera permission, allow the terminal/Codex process and rerun.
If the board appears upside down in the camera, prefer `DISPLAY_ROTATION=2 make visual-smoke` so the sketch renders OCR text upright for the camera. Use `OCR_ROTATE` only when you cannot change the displayed orientation.

`make camera-aligner` opens a SwiftPM macOS camera tuning tool. Use it to:

- preview the selected camera live
- adjust the OCR crop rectangle with sliders
- set OCR rotation for boards that appear upside down in the camera
- see Vision OCR results update live
- copy the generated `CAMERA_CROP` and `OCR_ROTATE` values for `make visual-smoke`

`make official-demos` lists the Waveshare official Arduino examples tracked in `config/official-demos.tsv`.
Use `make official-build DEMO=<id>` for compile-only validation, and `make official-smoke DEMO=<id>` to upload a vendor demo and verify its expected serial output. Start with `DEMO=01-helloworld`, then move through PMU, IMU, LVGL, and audio demos.
See `docs/p0-official-demos.md` for the current P0 bring-up matrix and local verification notes.
