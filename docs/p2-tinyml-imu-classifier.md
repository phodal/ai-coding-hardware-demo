# P2 TinyML IMU Classifier

The `tinyml_imu_classifier` sketch is a deterministic TinyML classifier for the QMI8658 IMU on the Waveshare ESP32-S3-Touch-AMOLED-1.75C. It uses a small nearest-centroid model table from `config/tinyml-imu-model.json` and validates the firmware, display, IMU sampling, serial control, and host automation path before replacing the embedded classifier with ESP-DL or a larger trained model.

## What It Proves

- The AMOLED can render the current inference state with large OCR-friendly `TINY OK` text.
- The QMI8658 IMU initializes and can feed live accelerometer and gyroscope samples.
- The firmware exposes model metadata, hash, prototype count, training sample count, validation accuracy, and status through a serial protocol.
- The host can evaluate the checked-in model metadata and inject deterministic feature vectors for all five labels without moving the physical board.

## Commands

```bash
make tinyml-imu-build
make tinyml-imu-model-check
make tinyml-imu-smoke
TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 OCR_ROTATE=180 make tinyml-imu-smoke
```

`make tinyml-imu-model-check` validates the checked-in nearest-centroid model metadata and validation set. The smoke script uploads the sketch, waits for `TINYML_READY`, verifies the board-reported model hash, disables live mode, sends known IMU samples, and verifies `REST`, `TILT_LEFT`, `TILT_RIGHT`, `FACE_UP`, and `SHAKE` classifications.

## Serial Protocol

- `PING` returns `PONG`.
- `MODEL?` emits `TINYML_MODEL name=imu_centroid_v1 type=nearest_centroid hash=tinyml-imu-centroid-v1 ...`.
- `STATUS?` emits `TINYML_STATUS`.
- `LIVE:1` and `LIVE:0` enable or disable live IMU inference.
- `SAMPLE:<ax>,<ay>,<az>,<gx>,<gy>,<gz>` injects one feature vector and emits `TINYML_CLASS`.

## Acceptance Gates

- Compile: `make tinyml-imu-build`
- Serial:
  - `TINYML_READY display=1 imu=1`
  - `TINYML_MODEL ... hash=tinyml-imu-centroid-v1 ... validation_accuracy=1.000 ... classes=REST,TILT_LEFT,TILT_RIGHT,FACE_UP,SHAKE`
  - `TINYML_CLASS source=serial label=REST`
  - `TINYML_CLASS source=serial label=TILT_LEFT`
  - `TINYML_CLASS source=serial label=TILT_RIGHT`
  - `TINYML_CLASS source=serial label=FACE_UP`
  - `TINYML_CLASS source=serial label=SHAKE`
- Visual: optional OCR sees the stable `TINY` marker on the AMOLED. The visual wrapper uses color preprocessing and wider scaling by default because gray preprocessing can drop the cyan/red AMOLED text.

## Notes

- This is a small TinyML validation model, not yet a production ESP-DL deployment.
- The current classifier is intentionally simple and embedded: nearest centroid over `ax,ay,az,gx,gy,gz`, with gyroscope axes scaled before distance scoring.
- Keep the serial sample path when replacing the classifier. It gives the Skill a deterministic way to validate model behavior without camera positioning or physical movement.
- This path is safe for late-night validation because it does not play audio or use the host microphone.

## Verified Locally

- `make tinyml-imu-model-check`: passed with `accuracy=1.000` over 10 validation samples and `min_confidence=0.689`.
- `make tinyml-imu-build`: passed with `439099 bytes` program storage and `23048 bytes` dynamic memory.
- `SKIP_BUILD=1 make tinyml-imu-smoke`: uploaded to `/dev/cu.usbmodem83101` and validated `hash=tinyml-imu-centroid-v1`, `prototypes=5`, `validation_accuracy=1.000`, and labels `REST,TILT_LEFT,TILT_RIGHT,FACE_UP,SHAKE`.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target tinyml-imu --skip-build --per-target-timeout 240 --max-failures 1"`: passed with summary `.logs/hardware-smoke-suite/20260614-054530/summary.json`.
- Observed summary: `tinyml_imu_summary classifications=5 labels=REST,TILT_LEFT,TILT_RIGHT,FACE_UP,SHAKE model=tinyml-imu-centroid-v1 min_confidence=0.914`.
- `SKIP_BUILD=1 TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 OCR_ROTATE=180 TINYML_IMU_SECONDS=3 CAMERA_CAPTURE_TIMEOUT=8 make tinyml-imu-smoke`: uploaded to `/dev/cu.usbmodem83101`, validated the same five serial-injected IMU labels with `min_confidence=0.914`, saved `.logs/camera-ocr-20260616-074921.jpg`, and passed camera OCR on `TINY`.
