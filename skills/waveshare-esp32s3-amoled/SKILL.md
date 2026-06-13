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
   - Camera capture is bounded by `CAMERA_CAPTURE_TIMEOUT`; if it times out before saving a frame, debug macOS camera availability or another app owning the camera before changing board firmware.
   - Run `make camera-diagnose` when capture fails; it records camera inventory, Swift AVFoundation status, related processes, and bounded video-only capture probes under `.logs/`.
   - Pass only if OCR sees `OK`; use the saved raw/processed images to debug focus, glare, rotation, or garbled output.

7. For official demo bring-up:
   - Run `make official-demos` to list the Waveshare Arduino demo manifest.
   - Run `make official-build-all` before debugging higher-level AI features; all official Arduino examples should compile first.
   - Run `SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld` to upload the official display baseline and verify runtime serial output.
   - The project runner stages vendor examples under `.arduino-build/official-sketches/<id>` because several official `.ino` filenames do not match their parent folder names, which `arduino-cli` requires.

8. For XiaoZhi AI bring-up:
   - Run `make xiaozhi-latest` to locate the latest official `waveshare-esp32-s3-touch-amoled-1.75c` release asset.
   - Run `make xiaozhi-inspect` before flashing; it should confirm the zip contains `merged-binary.bin`.
   - Run `make xiaozhi-flash` only when the user is ready to replace the current Arduino demo with XiaoZhi firmware.
   - For source builds, run `make xiaozhi-source-clone` then `make xiaozhi-source-check`; the local defaults select `CONFIG_BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_AMOLED_1_75C=y`.
   - If `idf.py` is missing, stop at source-check and tell the user to install/source ESP-IDF before `scripts/xiaozhi.sh idf-build`.

9. For the self-developed cloud AI terminal:
   - Run `make cloud-ai-build` to compile the board-side display/serial terminal.
   - Run `make cloud-ai-smoke` to upload it and verify the host serial relay reaches `AI_DISPLAYED`.
   - Run `CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make cloud-ai-smoke` when the camera is positioned for OCR; serial verifies `AI OK`, while OCR should at least see stable `OK`.
   - Treat this as the control-plane slice; ES7210 microphone input and ES8311 speaker output still need dedicated audio stream validation.

10. For microphone/audio-front-end validation:
   - Run `make audio-vad-build` to compile the ES7210 microphone probe.
   - Run `make audio-vad-smoke` to upload it, play a host-side `say` stimulus, and validate RMS/peak serial metrics.
   - Use `AUDIO_VAD_REQUIRE_SPEECH=1 make audio-vad-smoke` only when the host speaker is close enough for reliable VAD.
   - Use `AUDIO_VAD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make audio-vad-smoke` when camera OCR should verify the screen reaches `OK`.

11. For speaker/audio-output validation:
   - Run `make speaker-output-build` to compile the ES8311 speaker tone probe.
   - Run `make speaker-output-smoke` to upload it, trigger a 1 kHz / 1.5 kHz tone over serial, and validate the output through host microphone capture.
   - Use `SPEAKER_AUDIO_DEVICE=<avfoundation audio index>` when the default camera microphone is not close to the board speaker.
   - Use `SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make speaker-output-smoke` when camera OCR should verify the screen reaches `OK`.
   - Do not run audible speaker or microphone smoke tests late at night unless the user explicitly asks for them.

12. For PMU/IMU sensor validation:
   - Run `make sensor-status-build` to compile the AXP2101 + QMI8658 status probe.
   - Run `make sensor-status-smoke` to upload it and validate silent serial metrics from the PMU and IMU.
   - Use `SENSOR_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make sensor-status-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

13. For touch controller validation:
   - Run `make touch-status-build` to compile the CST92xx touch controller probe.
   - Run `make touch-status-smoke` to upload it and validate the touch controller is online through serial status and AMOLED OCR.
   - Use `TOUCH_REQUIRE_EVENT=1 make touch-status-smoke` only when a human can touch the screen during the smoke window.
   - Use `TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make touch-status-smoke` when camera OCR should verify the screen reaches `OK`.

14. For combined non-audio app validation:
   - Run `make interaction-dashboard-build` to compile the combined display, touch-controller, PMU, and IMU dashboard.
   - Run `make interaction-dashboard-smoke` to upload it and drive page changes, serial-simulated IMU gesture handling, brightness, standby, and wake transitions without requiring a human tap.
   - Use `INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make interaction-dashboard-smoke` when camera OCR should verify the final dashboard page reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

15. For LVGL visual-agent validation:
   - Run `make lvgl-visual-agent-build` to compile the repo-owned LVGL tabview app.
   - Run `make lvgl-visual-agent-smoke` to upload it and validate LVGL initialization, display flush, CST92xx touch input registration, chat bubbles, cards, settings, agent thoughts, and tab/page changes over serial.
   - Use `LVGL_VISUAL_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make lvgl-visual-agent-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as the agent-specific LVGL UI slice; the official `05-lvgl-widgets` demo remains the vendor baseline.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

16. For desktop AI widget validation:
   - Run `make desk-widget-build` to compile the serial-driven desktop widget.
   - Run `make desk-widget-smoke` to upload it and validate CI/GitHub/alert/timer/AI-summary pages without network credentials.
   - Use `DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make desk-widget-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

17. For IoT control panel validation:
   - Run `make iot-panel-build` to compile the serial-driven Home Assistant / MQTT / HTTP control panel.
   - Run `make iot-panel-smoke` to upload it and validate device state changes, MQTT-style inbound updates, HTTP-style outbound actions, and scenes without Wi-Fi credentials.
   - Use `IOT_PANEL_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make iot-panel-smoke` when camera OCR should verify the screen reaches `OK`.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

18. For offline voice-control state-machine validation:
   - Run `make offline-voice-build` to compile the WakeNet/MultiNet-facing serial harness.
   - Run `make offline-voice-smoke` to upload it and validate pre-wake command rejection, wake events, command recognition, runtime command add, continuous mode, sleep/wake state, and local actions without using the microphone.
   - Use `OFFLINE_VOICE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make offline-voice-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as the deterministic control-plane gate before wiring real ESP-SR audio frames and models.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

19. For TinyML / IMU classifier validation:
   - Run `make tinyml-imu-build` to compile the QMI8658 TinyML classifier scaffold.
   - Run `make tinyml-imu-smoke` to upload it, disable live IMU mode, inject deterministic serial feature vectors, and verify `REST`, `TILT_LEFT`, `TILT_RIGHT`, and `SHAKE` labels.
   - Use `TINYML_IMU_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make tinyml-imu-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as a TinyML automation harness. The current embedded classifier is intentionally simple and should be replaced by ESP-DL or a trained model later without removing the deterministic serial sample gate.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

20. For ESP-Claw / OpenClaw agent harness validation:
   - Run `make esp-claw-agent-build` to compile the Arduino compatibility harness for the ESP-Claw/OpenClaw direction.
   - Run `make esp-claw-agent-smoke` to upload it and validate local rule add, event sensing, rule decision, MCP-style tool invocation, IM chat input, tagged memory, and LLM fallback routing over serial.
   - Use `ESP_CLAW_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make esp-claw-agent-smoke` when camera OCR should verify the screen reaches `OK`.
   - Treat this as a deterministic control-plane harness, not the official ESP-Claw firmware image. It exists so automation can prove the agent loop before IM credentials, Wi-Fi, and full ESP-Claw source builds are introduced.
   - This path is safe for late-night validation because it does not play audio or use the host microphone.

21. For Skill automation wiring:
   - Run `scripts/waveshare-arduino-cli.sh verify <project-dir>` from this skill to prove the agent-facing entrypoint can inspect the toolchain, see the USB board, list official demos, and clean-compile `cloud_ai_terminal`, `audio_vad_probe`, `speaker_output_probe`, `sensor_status_probe`, `touch_status_probe`, `interaction_dashboard`, `lvgl_visual_agent`, `desk_widget`, `iot_control_panel`, `offline_voice_control`, `tinyml_imu_classifier`, and `esp_claw_agent`.
   - `verify`/`doctor` is intentionally compile-only; it does not upload firmware or run camera OCR.
   - Run explicit hardware smokes when the user wants board validation:
     `CLOUD_AI_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh cloud-ai <project-dir> smoke`
     `AUDIO_VAD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh audio-vad <project-dir> smoke`
     `SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh speaker-output <project-dir> smoke`
     `SENSOR_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh sensor-status <project-dir> smoke`
     `TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh touch-status <project-dir> smoke`
     `INTERACTION_DASHBOARD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh interaction-dashboard <project-dir> smoke`
     `LVGL_VISUAL_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh lvgl-visual-agent <project-dir> smoke`
     `DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh desk-widget <project-dir> smoke`
     `IOT_PANEL_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 scripts/waveshare-arduino-cli.sh iot-panel <project-dir> smoke`
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
make visual-smoke
make official-demos
make official-build-all
SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld
make xiaozhi-latest
make xiaozhi-inspect
make xiaozhi-source-check
make cloud-ai-build
make cloud-ai-smoke
make audio-vad-build
make audio-vad-smoke
make speaker-output-build
make speaker-output-smoke
make sensor-status-build
make sensor-status-smoke
make touch-status-build
make touch-status-smoke
make interaction-dashboard-build
make interaction-dashboard-smoke
make lvgl-visual-agent-build
make lvgl-visual-agent-smoke
make desk-widget-build
make desk-widget-smoke
make iot-panel-build
make iot-panel-smoke
make offline-voice-build
make offline-voice-smoke
make tinyml-imu-build
make tinyml-imu-smoke
make esp-claw-agent-build
make esp-claw-agent-smoke
/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh verify /path/to/project
```

## References

Read `references/board.md` when you need board facts, source links, library names, or troubleshooting notes.
