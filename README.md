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

## Workflow Map

Use the Arduino lane first when validating local toolchain, display, touch, PMU, IMU, and audio examples. Use the XiaoZhi lane only when you intend to replace the currently flashed Arduino sketch with the XiaoZhi firmware or inspect that firmware route.

## Arduino Commands

```bash
make setup
make build
make upload
make monitor
make smoke
make visual-smoke
make camera-aligner
make camera-diagnose
make feature-matrix-check
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
CAMERA_CAPTURE_ENGINE=auto
CAMERA_DEVICE=0
CAMERA_SIZE=1280x720
CAMERA_CROP="iw*0.55:ih*0.65:(iw-ow)/2:(ih-oh)/2"
OCR_ROTATE=0
DISPLAY_ROTATION=0
OCR_EXPECTED="OK"
OCR_ENGINE=vision
CAMERA_CAPTURE_TIMEOUT=15
```

Point the camera at the AMOLED before running the command. If macOS asks for camera permission, allow the terminal/Codex process and rerun.
If the board appears upside down in the camera, prefer `DISPLAY_ROTATION=2 make visual-smoke` so the sketch renders OCR text upright for the camera. Use `OCR_ROTATE` only when you cannot change the displayed orientation.
Camera capture is bounded by `CAMERA_CAPTURE_TIMEOUT` so automation fails clearly instead of hanging when the selected camera device is unavailable or already owned by another app. `CAMERA_CAPTURE_ENGINE=auto` prefers the SwiftPM `CameraSnapshot` tool and falls back to ffmpeg.

`make camera-aligner` opens a SwiftPM macOS camera tuning tool. Use it to:

- preview the selected camera live
- adjust the OCR crop rectangle with sliders
- set OCR rotation for boards that appear upside down in the camera
- see Vision OCR results update live
- copy the generated `CAMERA_CROP` and `OCR_ROTATE` values for `make visual-smoke`

`make camera-diagnose` writes a bounded diagnostic bundle under `.logs/camera-diagnose-*` with macOS camera inventory, Swift device status, camera-related processes, and optional Swift/ffmpeg video-only capture probes.

`make feature-matrix-check` verifies that each requested feature direction has matching Makefile, script/sketch, documentation, and Skill helper coverage. `make feature-matrix-doc` regenerates `docs/hardware-verification-matrix.md`.

`make official-demos` lists the Waveshare official Arduino examples tracked in `config/official-demos.tsv`.
Use `make official-build DEMO=<id>` for compile-only validation, and `make official-smoke DEMO=<id>` to upload a vendor demo and verify its expected serial output. Start with `DEMO=01-helloworld`, then move through PMU, IMU, LVGL, and audio demos.
See `docs/p0-official-demos.md` for the current P0 bring-up matrix and local verification notes.

## XiaoZhi AI Commands

```bash
make xiaozhi-latest
make xiaozhi-download
make xiaozhi-inspect
CONFIRM=--yes make xiaozhi-flash
make xiaozhi-source-clone
make xiaozhi-source-check
```

`make xiaozhi-latest`, `make xiaozhi-download`, and `make xiaozhi-inspect` automate the prebuilt XiaoZhi AI firmware route for `waveshare-esp32-s3-touch-amoled-1.75c`. `CONFIRM=--yes make xiaozhi-flash` writes the downloaded merged binary to the board and is intentionally explicit because it replaces the Arduino sketch currently on the device.

The source route uses `scripts/xiaozhi.sh idf-build`, `scripts/xiaozhi.sh idf-flash`, and `scripts/xiaozhi.sh idf-monitor` from an ESP-IDF shell where `idf.py` is available. See `docs/p0-xiaozhi-ai.md` for the current XiaoZhi acceptance notes.

## Git Hooks

```bash
make install-hooks
```

The versioned `pre-push` hook detects outgoing push refs or commit subjects that include `feat`. When it finds one, it updates the generated Feature Push Notes block in this README and stops the push so the README change can be reviewed and committed before pushing again.

## Cloud AI Terminal Commands

```bash
make cloud-ai-build
make cloud-ai-smoke
CLOUD_AI_PIPELINE=1 make cloud-ai-smoke
make cloud-ai-pipeline-smoke
CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make cloud-ai-smoke
make audio-vad-build
make audio-vad-smoke
make speaker-output-build
make speaker-output-smoke
make sensor-status-build
make sensor-status-smoke
make power-lifecycle-build
make power-lifecycle-smoke
make wifi-connectivity-build
make wifi-connectivity-smoke
make touch-status-build
make touch-status-smoke
make interaction-dashboard-build
make interaction-dashboard-smoke
make imu-interaction-build
make imu-interaction-smoke
make desk-widget-build
make desk-widget-smoke
make iot-panel-build
make iot-panel-smoke
make tinyml-imu-build
make tinyml-imu-smoke
make esp-claw-agent-build
make esp-claw-agent-smoke
make offline-voice-build
make offline-voice-smoke
make lvgl-visual-agent-build
make lvgl-visual-agent-smoke
```

`make cloud-ai-smoke` uploads the self-developed `cloud_ai_terminal` sketch, runs the host serial relay in mock mode, and verifies the board displays an AI response. `make cloud-ai-pipeline-smoke` drives the silent ASR -> LLM -> TTS serial pipeline and verifies `PIPELINE_DONE` without using the microphone or speaker. These slices validate the display and host/cloud protocol shape; real audio capture and speaker playback are tracked in `docs/p0-cloud-ai-terminal.md`.

`make audio-vad-smoke` uploads the ES7210 microphone probe, plays a host-side `say` stimulus, and validates serial RMS/peak metrics from the board. This is the microphone capture gate before full ASR streaming; details are in `docs/p0-audio-vad-probe.md`.

`make speaker-output-smoke` uploads the ES8311 speaker probe, sends `PLAY` over serial, records the board output through a host microphone, and validates the active audio window against baseline energy. Use `SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make speaker-output-smoke` when camera OCR should also verify `SPK OK`; details are in `docs/p0-speaker-output-probe.md`. Avoid running audible audio smokes late at night unless explicitly requested.

`make sensor-status-smoke` uploads the AXP2101 + QMI8658 probe and validates PMU/IMU serial metrics without using any audio device. Use `SENSOR_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make sensor-status-smoke` when camera OCR should also verify `SENS OK`; details are in `docs/p1-sensor-status-probe.md`.

`make power-lifecycle-smoke` uploads the AXP2101 power lifecycle probe and validates DIM, STANDBY, ACTIVE, brightness, capacity, load profile, wake, and runtime-estimate serial behavior without using audio devices. The default smoke does not require a connected battery because the battery connector may be unused; set `POWER_REQUIRE_BATTERY=1` only when a battery is connected. The automated standby keeps USB serial alive instead of entering true deep sleep; details are in `docs/p1-power-lifecycle-probe.md`.

`make wifi-connectivity-smoke` uploads the Wi-Fi connectivity probe and validates the ESP32-S3 radio with a scan-only default. It reports AP count, best RSSI, and connection state without printing SSID names or storing credentials. Set `WIFI_TEST_SSID` and `WIFI_TEST_PASSWORD` only for a supervised join check; details are in `docs/p1-wifi-connectivity-probe.md`.

`make touch-status-smoke` uploads the CST9217 touch-controller probe and validates that the controller is online. Use `TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make touch-status-smoke` for camera OCR, or `TOUCH_REQUIRE_EVENT=1 make touch-status-smoke` when a human can tap the screen during the smoke window; details are in `docs/p1-touch-status-probe.md`.

`make interaction-dashboard-smoke` uploads the combined non-audio dashboard and drives it with serial commands across HOME, IMU, PWR, and TOUCH pages. It validates display control flow, CST9217 controller presence, AXP2101 PMU metrics, QMI8658 IMU metrics, serial-simulated gesture handling, brightness, standby, and wake transitions in one sketch. Use `INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make interaction-dashboard-smoke` when camera OCR should also verify the screen reaches `OK`; details are in `docs/p1-interaction-dashboard.md`.

`make imu-interaction-smoke` uploads the dedicated QMI8658 interaction probe and validates wrist wake, shake-to-switch, posture menu, and step counting through deterministic serial-injected IMU samples. Use `IMU_INTERACTION_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make imu-interaction-smoke` when camera OCR should also verify the screen reaches `OK`; details are in `docs/p1-imu-interaction-probe.md`.

`make desk-widget-smoke` uploads the serial-driven desk widget and validates CI/GitHub/alert/timer/AI-summary pages without network credentials or audio devices. Use `DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make desk-widget-smoke` when camera OCR should also verify the screen reaches `OK`; details are in `docs/p1-desk-widget.md`.

`make iot-panel-smoke` uploads the serial-driven IoT control panel and validates device state changes, MQTT-style inbound updates, HTTP-style outbound actions, and scene changes without Wi-Fi credentials. Use `IOT_PANEL_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make iot-panel-smoke` when camera OCR should also verify the screen reaches `OK`; details are in `docs/p1-iot-control-panel.md`.

`make tinyml-imu-smoke` uploads the TinyML IMU classifier scaffold, disables live mode, injects deterministic accelerometer/gyroscope feature vectors over serial, and verifies `REST`, `TILT_LEFT`, `TILT_RIGHT`, and `SHAKE` labels. This is the model automation harness before replacing the embedded rule classifier with ESP-DL or a trained model; details are in `docs/p2-tinyml-imu-classifier.md`.

`make esp-claw-agent-smoke` uploads the ESP-Claw/OpenClaw Arduino harness and validates an agent control loop over serial: local rule add, event sensing, rule decision, MCP-style tool call, IM chat input, tagged memory write, and LLM fallback routing. This is a deterministic compatibility slice before replacing it with the official ESP-Claw firmware route; details are in `docs/p2-esp-claw-agent.md`.

`make offline-voice-smoke` uploads the offline voice-control harness and validates the WakeNet/MultiNet-facing state machine without using the microphone: pre-wake rejection, wake event, command recognition, runtime command add, continuous mode, sleep/wake, and local actions. This is the serial control-plane gate before wiring real ESP-SR audio; details are in `docs/p1-offline-voice-control.md`.

`make lvgl-visual-agent-smoke` uploads the repo-owned LVGL visual-agent surface and validates LVGL tabview pages for chat bubbles, cards, settings, and agent thoughts over serial. This complements the official LVGL widgets demo with an automatable agent UI; details are in `docs/p1-lvgl-visual-agent.md`.
