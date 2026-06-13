# Agent Notes

Recoding changes to the AGENTS.md file for better organization and clarity.

## Hardware Verification Practices

- Keep each hardware lane scriptable from `make`; interactive IDE state is not enough evidence.
- Prefer a narrow compile/upload/smoke loop before adding abstractions. For this board, clean Arduino CLI builds with dedicated `.arduino-build/<name>` paths avoid cache collisions.
- Treat serial output and camera OCR as complementary evidence: serial proves firmware control flow, while camera OCR proves the AMOLED actually renders expected text.
- Keep destructive actions explicit. Firmware replacement commands should require a visible confirmation variable or `--yes`.
- Stage vendor sketches instead of editing vendor sources when Arduino CLI requires folder and `.ino` names to match.
- Treat audible audio smokes as disruptive physical tests. Do not run speaker or microphone stimulus tests late at night unless the user explicitly asks for them.
- Prefer silent PMU/IMU/display validation when working late; serial metrics plus camera OCR can still produce strong evidence without using audio devices.

## Current Challenges

- The installed ESP32 Arduino core has no dedicated 1.75C FQBN, so the repo pins a generic ESP32-S3 FQBN with explicit flash/PSRAM/USB options.
- `arduino-cli monitor` can open but capture no bytes on the local USB Serial/JTAG port; raw `stty` plus `cat` is the reliable serial path.
- Camera OCR is sensitive to orientation, focus, glare, and pixel font shape. Use `make camera-aligner` and keep validation text large and simple.
- Vision OCR can misread `AI OK` as `HI OK`; use serial to verify the full payload and OCR a stable subset such as `OK`.
- Camera capture has a `CAMERA_CAPTURE_TIMEOUT` guard. If ffmpeg times out before saving a frame, treat it as host camera availability/ownership first, not as board display failure.
- Use `make camera-diagnose` when OCR capture fails. It records system camera inventory, Swift AVFoundation device status, related camera processes, and video-only capture probes without touching audio input.
- `pyserial` is not installed in the current Python, so host relay tools should use stdlib `termios` or document their dependency explicitly.
- Python `audioop` is not available in the current Python, so WAV analysis should use explicit PCM byte parsing or a documented dependency.
- ESP-IDF is not currently sourced in this shell, so XiaoZhi source builds can only be checked up to board configuration until `idf.py` is available.
- PMU validation should not require a nonzero battery voltage because the battery connector may be unused; gate on system voltage and use battery voltage as supporting evidence.
- Power lifecycle validation should not require a connected battery by default. `power-lifecycle-smoke` uses serial-preserving DIM/STANDBY/ACTIVE states, so it proves firmware power-control behavior without claiming true ESP32 deep sleep or measured current draw.
- Touch validation has two levels: default `touch-status-smoke` proves the CST9217 controller is online, while `TOUCH_REQUIRE_EVENT=1` requires a supervised human tap.

## Cloud AI Terminal Direction

- The first self-developed terminal slice uses serial relay control before direct audio streaming. This validates display rendering and host/cloud protocol shape without blocking on ASR/TTS integration.
- Move from mock/HTTP text responses to ES7210 microphone capture in small steps: first validate RMS/peak metrics, then require VAD speech, then stream audio for ASR.
- VAD is stricter than raw microphone capture. Treat RMS/peak threshold increases as the microphone data-flow gate, and use `AUDIO_VAD_REQUIRE_SPEECH=1` only when the host speaker is physically close enough.
- On the current desk setup, macOS `say` produced a clear ES7210 signal delta but did not trigger ESP-SR VAD; this is acceptable for the microphone data-flow gate but not for a wake-word or speech-command gate.
- ES8311 playback now has a board-generated tone probe and a host microphone gate. Treat the current gate as physical output evidence, not as proof of TTS quality or frequency accuracy.
- AXP2101 + QMI8658 now have a silent sensor-status probe. A stationary board should report accelerometer magnitude near 1 g; use the wider default range only as a smoke gate.
- The power lifecycle probe is the preferred P1 battery/low-power control gate. Keep its default path silent and serial-driven; only enable `POWER_REQUIRE_BATTERY=1` when a battery is physically connected.
- CST9217 touch now has a silent controller-online probe. Do not claim end-to-end touch UX without either the official LVGL widgets pass or a `TOUCH_REQUIRE_EVENT=1` manual tap pass.
- The LVGL visual-agent harness is the repo-owned proof for LVGL UI beyond vendor examples. Prefer it when validating chat/card/settings UI behavior; keep the official `05-lvgl-widgets` demo as the vendor baseline.
- The interaction dashboard is the preferred combined non-audio app smoke. It verifies display, touch-controller presence, PMU, and IMU through serial page switching plus optional OCR, without requiring a human tap or using any audio device.
- The interaction dashboard also has first-pass P1 behavior for IMU gestures and power management. Default automation uses serial-simulated gestures and power commands for determinism; real physical shake evidence should be reported separately as `DASH_GESTURE source=imu`.
- The LVGL visual-agent harness is the preferred P1 touch UI / visual-agent slice. It uses real LVGL widgets and a serial protocol for chat bubbles, cards, settings, and agent thoughts, so UI behavior can be tested without network or audio dependencies.
- The desk widget is the first P1 desktop-widget slice. It is intentionally serial-driven before direct Wi-Fi integrations, so CI/GitHub/calendar/LLM relays can be validated without credentials or audio devices.
- The IoT control panel is the first P1 Home Assistant/MQTT/HTTP slice. Keep it serial-driven until the UI/state model is stable, then bridge real network events through the same protocol before moving logic fully onto Wi-Fi firmware.
- The offline voice-control harness is a P1 non-audio gate for WakeNet/MultiNet behavior. Preserve the serial `WAKE:` and `CMD:` simulation path when adding real ESP-SR audio so late-night validation can still prove the command state machine without microphone or speaker use.
- The TinyML IMU classifier is a P2 model-automation scaffold. Keep deterministic serial `SAMPLE:` vectors as the Skill-facing acceptance path even after replacing the embedded rule classifier with ESP-DL or a trained model.
- The ESP-Claw/OpenClaw agent harness is a P2 compatibility scaffold, not the official ESP-Claw firmware. Preserve the serial `RULE:ADD` plus `EVENT` gate so Skill automation can prove sense/reason/decide/act behavior without IM credentials, Wi-Fi, camera, or audio.

## Feature Push README Hook

- This repo uses `.githooks/pre-push`; install it with `make install-hooks` or `git config core.hooksPath .githooks`.
- When an outgoing push ref or commit subject includes `feat`, the hook must update the generated `README.md` section between `<!-- feat-push-readme:start -->` and `<!-- feat-push-readme:end -->`.
- Because a pre-push hook cannot add a newly modified `README.md` to the already prepared push, the hook intentionally stops that push after updating the file. Commit the README change, then push again.
- AI agents changing feature behavior should keep `README.md` current before committing, and should not remove the generated marker block unless they also replace the hook behavior.
