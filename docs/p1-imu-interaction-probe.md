# P1 IMU Interaction Probe

## Purpose

`sketches/imu_interaction_probe` validates user-facing IMU interactions on the QMI8658:

- wrist wake
- shake-to-switch page
- posture-driven menu state
- step counting

The default smoke is deterministic and silent. It initializes the real IMU, then injects serial samples so automation does not require physically shaking the board.

## Commands

```bash
make imu-interaction-build
make imu-interaction-smoke
IMU_INTERACTION_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make imu-interaction-smoke
```

## Serial Contract

The board accepts:

- `PING`
- `STATUS?`
- `LIVE:0` / `LIVE:1`
- `SLEEP`
- `WAKE`
- `MENU:NEXT`
- `RESET`
- `SAMPLE:<ax>,<ay>,<az>,<gx>,<gy>,<gz>`

The board emits:

- `IMU_INTERACTION_READY display=... imu=...`
- `IMU_INTERACTION_STATUS ... awake=... page=... pose=... steps=...`
- `IMU_EVENT name=WRIST_WAKE ...`
- `IMU_EVENT name=SHAKE_SWITCH ...`
- `IMU_EVENT name=POSE_MENU ...`
- `IMU_EVENT name=STEP ...`
- `IMU_EVENT name=MENU_NEXT ...`

## Acceptance

`make imu-interaction-smoke` passes when:

- display and QMI8658 initialization are reported
- `PING` returns `PONG`
- serial sample injection wakes from sleep with `WRIST_WAKE`
- a shake sample changes page and emits `SHAKE_SWITCH`
- a tilt sample emits `POSE_MENU`
- a step sample increments `steps`
- explicit `MENU:NEXT` increments menu changes

## Verified Locally

- `make imu-interaction-build`: passed.
- `SKIP_BUILD=1 make imu-interaction-smoke`: uploaded to `/dev/cu.usbmodem83101` and validated `WRIST_WAKE`, `SHAKE_SWITCH`, `POSE_MENU`, `STEP`, and `MENU_NEXT`; final counters were `steps=1`, `shakes=1`, `wrist_wakes=1`, and `menu_changes=2`.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh imu-interaction /Users/phodal/hardware/arduino check --port /dev/cu.usbmodem83101 --seconds 1`: passed against the flashed sketch.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh imu-interaction /Users/phodal/hardware/arduino check --port /dev/cu.usbmodem83101 --seconds 1`: passed against the flashed sketch.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--targets cloud-ai-terminal,imu-interaction,desk-widget --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed `imu-interaction-smoke` on `/dev/cu.usbmodem83101`.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-045308/summary.json`.
- Latest target log: `.logs/hardware-smoke-suite/20260614-045308/imu-interaction.log`.
- Observed build size: `439115 bytes` program storage and `23120 bytes` dynamic memory.
- Observed summary: `imu_interaction_summary events=MENU_NEXT,POSE_MENU,SHAKE_SWITCH,SLEEP,STEP,WRIST_WAKE steps=1 shakes=1 wrist_wakes=1 menu_changes=2`.
- `SKIP_BUILD=1 IMU_INTERACTION_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 IMU_INTERACTION_SECONDS=2 CAMERA_CAPTURE_TIMEOUT=8 make imu-interaction-smoke`: uploaded to `/dev/cu.usbmodem83101`, validated `WRIST_WAKE`, `SHAKE_SWITCH`, `POSE_MENU`, `STEP`, and `MENU_NEXT`, and camera OCR matched `OK`.
- Camera OCR artifacts: `.logs/camera-ocr-20260616-080027.jpg`, `.logs/camera-ocr-20260616-080027.processed.png`, `.logs/camera-ocr-20260616-080027.txt`.
- Latest visual build size: `439111 bytes` program storage and `23120 bytes` dynamic memory.

## Notes

Keep the serial `SAMPLE:` gate even if richer live gesture logic is added later. It gives the Skill a deterministic non-audio acceptance path and lets physical movement evidence be reported separately.
