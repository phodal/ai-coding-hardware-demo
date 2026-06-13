# P1 Interaction Dashboard

The `interaction_dashboard` sketch is the first combined non-audio app surface for the Waveshare ESP32-S3-Touch-AMOLED-1.75C. It drives the AMOLED, CST9217 touch controller, AXP2101 PMU, and QMI8658 IMU in one firmware image.

## What It Proves

- The display can render a usable multi-page UI with large OCR-friendly status text.
- The touch controller initializes and can switch pages with left/right taps.
- The PMU reports system, VBUS, and battery voltage metrics.
- The IMU reports accelerometer and gyroscope metrics.
- IMU shake gestures can switch the dashboard to the IMU page, with serial simulation available for automation.
- Brightness, idle dimming, standby, and wake transitions can be driven over serial.
- Automation can validate the UI without manual tapping by sending serial commands.

## Commands

```bash
make interaction-dashboard-build
make interaction-dashboard-smoke
INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make interaction-dashboard-smoke
```

The smoke script uploads the sketch, waits for `DASH_READY`, sends `PING`, then drives page changes with `PAGE:IMU`, `PAGE:PWR`, `PAGE:TOUCH`, and `PAGE:HOME`. It then exercises `BRIGHT:64`, `GESTURE:SHAKE`, `POWER:STANDBY`, and `POWER:WAKE` before validating `DASH_STATUS` metrics.

If `INTERACTION_DASHBOARD_VISUAL_SMOKE=1` is set, the wrapper also runs `scripts/camera-ocr.sh`. Camera capture is bounded by `CAMERA_CAPTURE_TIMEOUT` and may fail independently when the selected macOS camera device is unavailable or held by another app. In that case, the serial page-flow evidence still proves the board-side dashboard and sensors are running; rerun OCR after fixing the camera device.

## Serial Protocol

- `PING` returns `PONG`.
- `PAGE:HOME`, `PAGE:IMU`, `PAGE:PWR`, and `PAGE:TOUCH` switch dashboard pages.
- `NEXT` and `PREV` cycle pages.
- `GESTURE:SHAKE`, `GESTURE:TILT_LEFT`, and `GESTURE:TILT_RIGHT` simulate IMU gestures for automation.
- `BRIGHT:<8-255>` sets the active brightness.
- `POWER:STANDBY`, `POWER:DIM`, and `POWER:WAKE` drive the display power state.
- `IDLE:<milliseconds>` changes the idle dim threshold; `IDLE:0` disables automatic dimming.
- `DASH_READY display=1 pmu=1 imu=1 touch=1` indicates the combined hardware surface is online.
- `DASH_STATUS ... system_mv=... amag=... power=... brightness=... gestures=...` carries the PMU, IMU, power, and gesture smoke metrics.
- `DASH_TOUCH_EVENT ...` is emitted when the screen is tapped.
- `DASH_GESTURE ...` is emitted by real IMU shake detection or serial-simulated gestures.
- `DASH_POWER ...` is emitted after brightness, dim, standby, and wake transitions.

## Notes

This probe is safe for late-night validation: it does not play audio, use the host microphone, or require audible stimulus. The default smoke requires the touch controller to report online, but it does not require a human tap. Use the separate `touch-status-smoke` with `TOUCH_REQUIRE_EVENT=1` when supervised physical tap evidence is needed.
The default smoke uses `GESTURE:SHAKE` to make the gesture path deterministic; real IMU shake detection is implemented in firmware and can be observed as `DASH_GESTURE type=SHAKE source=imu` when the board is physically moved.
