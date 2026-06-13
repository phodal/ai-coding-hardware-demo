# P2 TinyML IMU Classifier

The `tinyml_imu_classifier` sketch is a deterministic TinyML scaffold for the QMI8658 IMU on the Waveshare ESP32-S3-Touch-AMOLED-1.75C. It validates the firmware, display, IMU sampling, serial control, and host automation path before replacing the embedded classifier with ESP-DL or a trained model.

## What It Proves

- The AMOLED can render the current inference state with large OCR-friendly `TINY OK` text.
- The QMI8658 IMU initializes and can feed live accelerometer and gyroscope samples.
- The firmware exposes model metadata and status through a serial protocol.
- The host can inject deterministic feature vectors and verify expected labels without moving the physical board.

## Commands

```bash
make tinyml-imu-build
make tinyml-imu-smoke
TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make tinyml-imu-smoke
```

The smoke script uploads the sketch, waits for `TINYML_READY`, disables live mode, sends known IMU samples, and verifies `REST`, `TILT_LEFT`, `TILT_RIGHT`, and `SHAKE` classifications.

## Serial Protocol

- `PING` returns `PONG`.
- `MODEL?` emits `TINYML_MODEL name=imu_baseline ...`.
- `STATUS?` emits `TINYML_STATUS`.
- `LIVE:1` and `LIVE:0` enable or disable live IMU inference.
- `SAMPLE:<ax>,<ay>,<az>,<gx>,<gy>,<gz>` injects one feature vector and emits `TINYML_CLASS`.

## Acceptance Gates

- Compile: `make tinyml-imu-build`
- Serial:
  - `TINYML_READY display=1 imu=1`
  - `TINYML_MODEL ... classes=REST,TILT_LEFT,TILT_RIGHT,FACE_UP,SHAKE`
  - `TINYML_CLASS source=serial label=REST`
  - `TINYML_CLASS source=serial label=TILT_LEFT`
  - `TINYML_CLASS source=serial label=TILT_RIGHT`
  - `TINYML_CLASS source=serial label=SHAKE`
- Visual: optional OCR sees `OK` on the AMOLED.

## Notes

- This is a TinyML validation harness, not yet a trained production model.
- The current classifier is intentionally simple and embedded: acceleration orientation rules plus gyroscope and acceleration magnitude gates.
- Keep the serial sample path when replacing the classifier. It gives the Skill a deterministic way to validate model behavior without camera positioning or physical movement.
- This path is safe for late-night validation because it does not play audio or use the host microphone.

## Verified Locally

- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--targets esp-claw-agent,tinyml-imu --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed `tinyml-imu-smoke` on `/dev/cu.usbmodem83101`.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-044424/summary.json`.
- Latest target log: `.logs/hardware-smoke-suite/20260614-044424/tinyml-imu.log`.
- Observed build size: `438763 bytes` program storage and `23048 bytes` dynamic memory.
- Observed summary: `tinyml_imu_summary classifications=4 labels=REST,TILT_LEFT,TILT_RIGHT,SHAKE min_confidence=0.823`.
