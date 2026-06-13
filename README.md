# Waveshare ESP32-S3 Touch AMOLED 1.75C Arduino CLI

This workspace automates build, upload, and serial monitoring for the Waveshare ESP32-S3-Touch-AMOLED-1.75C using `arduino-cli`.

## Current Tested Baseline

- `arduino-cli` 1.5.1
- `esp32:esp32` core 3.3.5
- Port: `/dev/cu.usbmodem83101`
- Sketch: `sketches/codex_hello_world`
- Vendor examples/libraries: `/Users/phodal/Downloads/ESP32-S3-Touch-AMOLED-1.75C-main/examples/Arduino-v3.3.5`

The installed ESP32 core does not currently expose a dedicated `ESP32-S3-Touch-AMOLED-1.75C` FQBN. The scripts use `esp32:esp32:esp32s3` with explicit board options and the Waveshare 1.75C `pin_config.h`.

## Commands

```bash
make setup
make build
make upload
make monitor
make smoke
```

Override defaults with environment variables or `.env`:

```bash
ARDUINO_PORT=/dev/cu.usbmodem83101 make upload
WAVESHARE_VENDOR_DIR=/path/to/ESP32-S3-Touch-AMOLED-1.75C-main make build
```

`make smoke` builds with a dedicated build directory, uploads, then records a short serial monitor log under `.logs/`.

