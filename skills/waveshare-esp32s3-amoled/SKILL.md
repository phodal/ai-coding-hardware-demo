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
   - On macOS, prefer raw serial capture with `stty -f "$PORT" 115200 cs8 -cstopb -parenb -ixon -ixoff -echo` followed by `cat "$PORT"`.
   - Use `arduino-cli monitor --config baudrate=115200,dtr=on,rts=off` only as a fallback; it may open successfully but capture no bytes on this USB Serial/JTAG path.
   - Treat repeated sketch serial lines plus visible AMOLED output as the baseline pass condition.

6. For visual display validation:
   - Upload `sketches/display_ocr_check` when the project has it.
   - If OCR framing or orientation is uncertain, run `make camera-aligner` first. Copy the generated `CAMERA_CROP='...' OCR_ROTATE=...` environment values.
   - If the board appears upside down in the camera, prefer `DISPLAY_ROTATION=2 make visual-smoke` so the sketch renders upright text for OCR.
   - Run `CAMERA_CROP='...' OCR_ROTATE=... DISPLAY_ROTATION=... make visual-smoke` to capture one camera frame with `ffmpeg` and OCR it with macOS Vision.
   - For bright AMOLED overexposure or color mismatch, start with the calibration sketch: `DISPLAY_ROTATION=2 DISPLAY_BRIGHTNESS=96 OCR_PREPROCESS_MODE=color CAMERA_EXPOSURE_POINT=0.5,0.65 CAMERA_FOCUS_POINT=0.5,0.65 COLOR_SWATCH_CHECK=1 make visual-smoke`. It renders large `OK` text plus red/green/blue/yellow swatches, then reports the largest connected color blocks, average RGB, centroids, and row/order geometry.
   - Use `make camera-color-check IMAGE=/path/to/raw.jpg` to check red/green/blue/yellow swatches on an existing camera image without OCR. Tune with `COLOR_SWATCH_MIN_X_GAP`, `COLOR_SWATCH_MAX_Y_SPREAD`, or `COLOR_SWATCH_GEOMETRY=0` only when the camera angle demands it.
   - Use `CAMERA_RAW_IMAGE=/path/to/raw.jpg ./scripts/camera-ocr.sh` to retune crop, rotation, or `OCR_PREPROCESS_MODE` without recapturing.
   - Camera capture is bounded by `CAMERA_CAPTURE_TIMEOUT`; if it times out before saving a frame, debug macOS camera availability or another app owning the camera before changing board firmware.
   - Run `make camera-ready` before expensive visual smokes when camera availability is uncertain; it uses Swift capture only and fails unless a frame is saved. Run `make camera-diagnose` when capture fails; it records camera inventory, Swift AVFoundation status, related processes, and bounded video-only capture probes under `.logs/`. Use `CAMERA_DIAGNOSE_FFMPEG=0` when you want to avoid ffmpeg device enumeration. If Swift diagnostics report `running=true frames=0 drops=0`, the capture session started but macOS/USB delivered no video buffers, so fix the host camera pipeline before rerunning board smokes.
   - Pass only if OCR sees `OK`; use the saved raw/processed images to debug focus, glare, rotation, or garbled output.

7. For official demo bring-up:
   - Run `make official-demos` to list the Waveshare Arduino demo manifest.
   - Run `make official-build-all` before debugging higher-level AI features; all official Arduino examples should compile first.
   - Run `make official-audio-preflight` when audio should stay quiet; it compiles only the official ES7210/ES8311 demos and checks source/serial markers without uploading or using audio devices.
   - Run `make official-coverage` for a read-only audit of build artifacts, source presence, quiet audio marker readiness, and existing physical smoke logs across every official demo.
   - Run `SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld` to upload the official display baseline and verify runtime serial output.
   - Official smoke uses `scripts/serial-capture.py` to open capture before RTS reset; keep this path for one-shot setup logs.
   - `03-power-axp2101` uses a staged-only `OFFICIAL_POWER_WIFI_TIMEOUT_MS` patch in automation so invalid vendor Station credentials do not block AP, PMU, and LVGL initialization; treat the resulting `Setup done` as PMU/LVGL evidence, not Station Wi-Fi proof.
   - The project runner stages vendor examples under `.arduino-build/official-sketches/<id>` because several official `.ino` filenames do not match their parent folder names, which `arduino-cli` requires.

8. For feature coverage auditing:
   - Run `make feature-matrix-check` to verify all 12 requested feature directions have matching Makefile targets, scripts/sketches, docs, and Skill helper wiring.
   - Run `make feature-matrix-doc` after changing `config/feature-matrix.tsv` to regenerate `docs/hardware-verification-matrix.md`.
   - Run `make hardware-evidence-audit` to identify lanes with missing `Verified Locally` sections or missing smoke-suite evidence.
   - Run `make hardware-evidence-doc` to regenerate `docs/hardware-evidence-audit.md`.
   - Run `make visual-evidence-audit` to identify lanes that lack recorded camera/OCR artifacts in their local evidence sections.
   - Run `make visual-evidence-doc` to regenerate `docs/visual-evidence-audit.md`.
   - Run `make goal-completion-audit` for the stricter requirement-level completion gate; use `python3 scripts/goal-completion-audit.py --strict` only when a non-zero result should fail CI or handoff.
   - Run `make goal-completion-doc` to regenerate `docs/goal-completion-audit.md`.
   - Run `make hardware-smoke-list` to inspect the default serialized non-audio smoke selection.
   - Run `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target <id>"` for a narrow serialized hardware lane; the default suite skips audio, conditional, and external lanes.
   - Run `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target xiaozhi-ai --allow-external"` for the non-destructive XiaoZhi firmware archive check; it does not flash firmware or use audio hardware.
   - Treat matrix status values as coverage metadata, not proof that a partial or external feature is complete.

9. For XiaoZhi AI bring-up:
   - Run `make xiaozhi-latest` to locate the latest official `waveshare-esp32-s3-touch-amoled-1.75c` release asset.
   - Run `make xiaozhi-inspect` before flashing; it should confirm the zip contains `merged-binary.bin`.
   - Run `make xiaozhi-preflight` for the non-destructive readiness gate; it hashes `merged-binary.bin`, reports esptool/serial/source/ESP-IDF readiness, and confirms `destructive=0 audio=0`.
   - Run `make xiaozhi-backup` before any XiaoZhi flash; it reads the current board flash to `.vendor/xiaozhi/backups/` and prints `xiaozhi_backup_summary ... destructive=0 audio=0`. The backup path defaults to `--no-stub` at `XIAOZHI_BACKUP_BAUD=115200` because long stub reads can stop on this USB Serial/JTAG path.
   - Run `BACKUP=<path> CONFIRM=--yes make xiaozhi-restore` only when you intentionally want to write a saved flash image back to the board.
   - Run `make xiaozhi-flash` only when the user is ready to replace the current Arduino demo with XiaoZhi firmware.
   - After an approved XiaoZhi flash, run `make xiaozhi-runtime-check` before any audio interaction. It captures serial logs after an RTS reset, looks for XiaoZhi onboarding or activation markers, and reports `xiaozhi_runtime_summary ... destructive=0 audio=0`.
   - Run `make xiaozhi-visual-check` for a camera-only OCR gate, or `make xiaozhi-runtime-visual-check` for serial plus AMOLED OCR after an approved flash. These gates do not use microphone or speaker hardware.
   - For source builds, run `make xiaozhi-source-clone` then `make xiaozhi-source-check`; the local defaults select `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C=y`.
   - Run `make xiaozhi-idf-env` to prove the local ESP-IDF shell can be activated without flashing firmware or using audio hardware.
   - Run `make xiaozhi-idf-build` to compile XiaoZhi from source without flashing; the script prints `xiaozhi_idf_build_summary ... destructive=0 audio=0` on success.
   - The current source requires ESP-IDF `>=5.5.2`; the local default is `.vendor/esp-idf-v5.5.4` with `~/.espressif/python_env/idf5.5_py3.14_env`.

10. For the self-developed cloud AI terminal:
   - Run `make cloud-ai-build` to compile the board-side display/serial terminal.
   - Run `make cloud-ai-smoke` to upload it and verify the host serial relay reaches `AI_DISPLAYED`.
   - Run `make cloud-ai-pipeline-smoke` to upload it and verify the silent ASR -> LLM -> TTS serial pipeline reaches `PIPELINE_DONE`.
   - Run `make cloud-ai-cache-smoke` to upload it and verify board-local NVS cache, session id, cloud request id, recoverable cloud error metrics, and `STATE?` runtime status commands.
   - Run `CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make cloud-ai-smoke` when the camera is positioned for OCR; serial verifies `AI OK`, while OCR should at least see stable `OK`.
   - Treat this as the verified non-audio cloud terminal control-plane slice; pipeline smoke does not use microphone or speaker hardware. ES7210 microphone input and ES8311 speaker output still need dedicated audio stream validation in an allowed audio window.

11. For microphone/audio-front-end validation:
   - Run `make audio-vad-build` to compile the ES7210 microphone probe.
   - Run `make audio-afe-readiness` when audio should stay quiet and you only need machine-readable AFE readiness; it rebuilds and reports implemented source/build/checker readiness versus source-integration and physical-audio requirements.
   - Run `make audio-vad-preflight` when audio should stay quiet; it rebuilds and checks artifacts, serial port, ES7210 source markers, checker options, and `config/audio-afe-profile.tsv` without uploading, playing stimulus, or opening audio devices.
   - Treat the AFE profile as coverage metadata: ES7210 capture and ESP-SR VAD are implemented, while AEC, noise suppression, and real WakeNet audio frames still require source integration and physical audio evidence.
   - Run `make audio-vad-smoke` to upload it, play a host-side `say` stimulus, and validate RMS/peak serial metrics.
   - Use `AUDIO_VAD_REQUIRE_SPEECH=1 make audio-vad-smoke` only when the host speaker is close enough for reliable VAD.
   - Use `AUDIO_VAD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make audio-vad-smoke` when camera OCR should verify the screen reaches `OK`.

12. For speaker/audio-output validation:
   - Run `make speaker-output-build` to compile the ES8311 speaker tone probe.
   - Run `make speaker-output-smoke` to upload it, trigger a 1 kHz / 1.5 kHz tone over serial, and validate the output through host microphone capture.
   - Use `SPEAKER_AUDIO_DEVICE=<avfoundation audio index>` when the default camera microphone is not close to the board speaker.
   - Use `SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make speaker-output-smoke` when camera OCR should verify the screen reaches `OK`.
   - Do not run audible speaker or microphone smoke tests late at night unless the user explicitly asks for them.

13. For PMU/IMU sensor validation:
   - Run `make sensor-status-build` to compile the AXP2101 + QMI8658 status probe.
   - Run `make sensor-status-smoke` to upload it and validate silent serial metrics from the PMU and IMU.
   - Use `SENSOR_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make sensor-status-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

14. For battery and low-power lifecycle validation:
   - Run `make power-lifecycle-build` to compile the AXP2101 power lifecycle probe.
   - Run `make power-lifecycle-smoke` to upload it and validate DIM, STANDBY, ACTIVE, brightness, capacity, load-profile, wake, and runtime-estimate serial behavior.
   - Use `POWER_REQUIRE_BATTERY=1 make power-lifecycle-smoke` only when a battery is physically connected; the default smoke should not fail USB-only benches.
   - Use `POWER_LIFECYCLE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make power-lifecycle-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone. Its standby mode keeps serial alive and should not be treated as proof of true ESP32 deep sleep or measured current draw.

15. For Wi-Fi connectivity validation:
   - Run `make wifi-connectivity-build` to compile the ESP32-S3 Wi-Fi scan/join probe.
   - Run `make wifi-connectivity-smoke` to upload it and validate Wi-Fi radio initialization plus scan completion without storing credentials.
   - Use `WIFI_TEST_SSID=... WIFI_TEST_PASSWORD=... make wifi-connectivity-smoke` only for a supervised join check; never commit SSIDs or passwords.
   - Use `WIFI_CONNECTIVITY_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make wifi-connectivity-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone. The default serial log avoids printing SSID names.

16. For touch controller validation:
   - Run `make touch-status-build` to compile the CST92xx touch controller probe.
   - Run `make touch-status-smoke` to upload it and validate the touch controller is online through serial status and AMOLED OCR.
   - Use `TOUCH_REQUIRE_EVENT=1 make touch-status-smoke` only when a human can touch the screen during the smoke window.
   - Use `TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make touch-status-smoke` when camera OCR should verify the screen reaches `OK`.

17. For combined non-audio app validation:
   - Run `make interaction-dashboard-build` to compile the combined display, touch-controller, PMU, and IMU dashboard.
   - Run `make interaction-dashboard-smoke` to upload it and drive page changes, serial-simulated IMU gesture handling, brightness, standby, and wake transitions without requiring a human tap.
   - Use `INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make interaction-dashboard-smoke` when camera OCR should verify the final dashboard page reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

18. For dedicated IMU interaction validation:
   - Run `make imu-interaction-build` to compile the QMI8658 wrist wake, shake switch, posture menu, and step counter probe.
   - Run `make imu-interaction-smoke` to upload it and validate deterministic serial-injected IMU samples for `WRIST_WAKE`, `SHAKE_SWITCH`, `POSE_MENU`, `STEP`, and `MENU_NEXT`.
   - Use `IMU_INTERACTION_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make imu-interaction-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio, use the host microphone, or require physically shaking the board.

19. For LVGL visual-agent validation:
   - Run `make lvgl-visual-agent-build` to compile the repo-owned LVGL tabview app.
   - Run `make lvgl-visual-agent-smoke` to upload it and validate LVGL initialization, display flush, CST92xx touch input registration, chat bubbles, cards, settings, agent thoughts, and tab/page changes over serial.
   - Use `LVGL_VISUAL_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make lvgl-visual-agent-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as the agent-specific LVGL UI slice; the official `05-lvgl-widgets` demo remains the vendor baseline.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

20. For desktop AI widget validation:
   - Run `make desk-widget-build` to compile the serial-driven desktop widget.
   - Run `make desk-widget-smoke` to upload it and validate CI/GitHub/alert/calendar/timer/AI-summary pages without network credentials.
   - Run `make desk-widget-relay-smoke` to validate the host event adapter that maps mock, JSON, or HTTP events into the widget serial protocol.
   - Use `DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make desk-widget-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

21. For IoT control panel validation:
   - Run `make iot-panel-build` to compile the serial-driven Home Assistant / MQTT / HTTP control panel.
   - Run `make iot-panel-smoke` to upload it and validate device state changes, explicit `IOT_HA` Home Assistant service calls, MQTT-style inbound updates, HTTP-style outbound actions, and scenes without Wi-Fi credentials.
   - Run `make iot-panel-relay-smoke` to validate the host event adapter that maps mock, JSON, or HTTP smart-home events into the panel serial protocol, including board-side `IOT_HA` output and the `ha=` state counter.
   - Use `IOT_PANEL_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make iot-panel-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

22. For offline voice-control state-machine validation:
   - Run `make offline-voice-build` to compile the WakeNet/MultiNet-facing serial harness.
   - Run `make offline-voice-smoke` to upload it and validate pre-wake command rejection, wake events, command recognition, runtime command add/modify/delete, continuous mode, sleep/wake state, and local actions without using the microphone.
   - Use `OFFLINE_VOICE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make offline-voice-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as the deterministic control-plane gate before wiring real ESP-SR audio frames and models.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

23. For TinyML / IMU classifier validation:
   - Run `make tinyml-imu-model-check` to validate the checked-in nearest-centroid model metadata and validation set.
   - Run `make tinyml-imu-build` to compile the QMI8658 TinyML classifier.
   - Run `make tinyml-imu-smoke` to upload it, verify the board-reported model hash, disable live IMU mode, inject deterministic serial feature vectors, and verify `REST`, `TILT_LEFT`, `TILT_RIGHT`, `FACE_UP`, and `SHAKE` labels.
   - Use `TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make tinyml-imu-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as a small TinyML automation model. The current embedded nearest-centroid classifier can be replaced by ESP-DL or a larger trained model later without removing the deterministic serial sample gate.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

24. For ESP-Claw / OpenClaw agent harness validation:
   - Run `make esp-claw-agent-build` to compile the Arduino compatibility harness for the ESP-Claw/OpenClaw direction.
   - Run `make esp-claw-agent-smoke` to upload it and validate local rule add, Lua-style rule loading, event sensing, rule decision, MCP-style tool registration/invocation, IM chat input, tagged memory put/get, and LLM fallback routing over serial.
   - Use `ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make esp-claw-agent-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as a deterministic compatibility harness, not the official ESP-Claw firmware image. It exists so automation can prove the agent loop before IM credentials, Wi-Fi, and full ESP-Claw source builds are introduced.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

25. For Skill automation wiring:
   - Run `scripts/waveshare-arduino-cli.sh verify <project-dir>` from this skill to prove the agent-facing entrypoint can inspect the toolchain, see the USB board, list official demos, and clean-compile `cloud_ai_terminal`, `audio_vad_probe`, `speaker_output_probe`, `sensor_status_probe`, `power_lifecycle_probe`, `wifi_connectivity_probe`, `touch_status_probe`, `interaction_dashboard`, `imu_interaction_probe`, `lvgl_visual_agent`, `desk_widget`, `iot_control_panel`, `offline_voice_control`, `tinyml_imu_classifier`, and `esp_claw_agent`.
   - Run `scripts/waveshare-arduino-cli.sh feature-matrix <project-dir> check` to validate coverage metadata before claiming all 12 requested directions are wired.
   - Run `scripts/waveshare-arduino-cli.sh visual-evidence <project-dir> audit` to check camera/OCR evidence coverage through the Skill helper.
   - Run `make claude-skill-smoke` from this repo to ask the local Claude CLI to read the repo Skill and invoke this helper for the non-audio visual smoke path. The wrapper records Claude's transcript plus the command log under `.logs/`, and `CLAUDE_SKILL_SMOKE_MODE=audit` switches to a no-upload feature-matrix check.
   - `verify`/`doctor` is intentionally compile-only; it does not upload firmware or run camera OCR.
   - Run explicit hardware smokes when the user wants board validation:
     `CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh cloud-ai <project-dir> smoke`
     `CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh cloud-ai <project-dir> pipeline`
     `scripts/waveshare-arduino-cli.sh cloud-ai <project-dir> cache`
     `scripts/waveshare-arduino-cli.sh audio-vad <project-dir> readiness`
     `AUDIO_VAD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh audio-vad <project-dir> smoke`
     `SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh speaker-output <project-dir> smoke`
     `SENSOR_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh sensor-status <project-dir> smoke`
     `POWER_LIFECYCLE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh power-lifecycle <project-dir> smoke`
     `WIFI_CONNECTIVITY_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh wifi-connectivity <project-dir> smoke`
     `TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh touch-status <project-dir> smoke`
     `INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh interaction-dashboard <project-dir> smoke`
     `IMU_INTERACTION_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh imu-interaction <project-dir> smoke`
     `LVGL_VISUAL_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh lvgl-visual-agent <project-dir> smoke`
     `DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh desk-widget <project-dir> smoke`
     `scripts/waveshare-arduino-cli.sh desk-widget <project-dir> relay`
     `IOT_PANEL_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh iot-panel <project-dir> smoke`
     `scripts/waveshare-arduino-cli.sh iot-panel <project-dir> relay`
     `OFFLINE_VOICE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh offline-voice <project-dir> smoke`
     `TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh tinyml-imu <project-dir> smoke`
     and
     `ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh esp-claw-agent <project-dir> smoke`.

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

For visual validation in this repo, prefer:

```bash
SMOKE_SECONDS=8 ./scripts/smoke.sh
make camera-aligner
make camera-diagnose
make camera-ready
make feature-matrix-check
make feature-matrix-doc
make hardware-evidence-audit
make hardware-evidence-doc
make visual-evidence-audit
make visual-evidence-doc
make goal-completion-audit
make goal-completion-doc
make hardware-smoke-list
make hardware-smoke-suite
make visual-smoke
make official-demos
make official-build-all
make official-audio-preflight
make official-coverage
SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld
make xiaozhi-latest
make xiaozhi-inspect
make xiaozhi-preflight
make xiaozhi-backup
make xiaozhi-runtime-check
make xiaozhi-visual-check
make xiaozhi-runtime-visual-check
make xiaozhi-source-check
make xiaozhi-idf-env
make xiaozhi-idf-build
make cloud-ai-build
make cloud-ai-smoke
make cloud-ai-pipeline-smoke
make cloud-ai-cache-smoke
make audio-vad-build
make audio-afe-readiness
make audio-vad-preflight
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
make lvgl-visual-agent-build
make lvgl-visual-agent-smoke
make desk-widget-build
make desk-widget-smoke
make desk-widget-relay-smoke
make iot-panel-build
make iot-panel-smoke
make iot-panel-relay-smoke
make offline-voice-build
make offline-voice-smoke
make tinyml-imu-model-check
make tinyml-imu-build
make tinyml-imu-smoke
make esp-claw-agent-build
make esp-claw-agent-smoke
/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh verify /path/to/project
```

## References

Read `references/board.md` when you need board facts, source links, library names, or troubleshooting notes.
