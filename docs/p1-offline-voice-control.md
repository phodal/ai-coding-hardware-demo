# P1 Offline Voice Control Harness

The `offline_voice_control` sketch is a non-audio Arduino harness for the offline voice-control direction. It validates the WakeNet/MultiNet-facing state machine without using the microphone at night: the host injects wake-word and command-recognition results over serial, while the board updates local UI and device state.

Reference context:

- WakeNet is Espressif's wake-word engine for wake-word detection on ESP32-S3: https://github.com/espressif/esp-sr
- MultiNet is Espressif's offline speech-command model for ESP32-S3 and supports runtime command changes: https://docs.espressif.com/projects/esp-sr/en/latest/esp32s3/speech_command_recognition/README.html

## What It Proves

- The AMOLED can render an offline voice surface with OCR-friendly `VOICE OK` text.
- The CST9217 touch controller initializes and can cycle pages.
- The local state machine rejects commands before wake, accepts commands after wake, supports continuous mode, and updates device actions.
- Runtime command add, modify, and delete work through a deterministic serial protocol that can later map to MultiNet command updates.

## Commands

```bash
make offline-voice-build
make offline-voice-smoke
OFFLINE_VOICE_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make offline-voice-smoke
```

The smoke script uploads the harness, sends `WAKE:` and `CMD:` events, validates command rejection before wake, adds/modifies/deletes a runtime command, toggles continuous mode, and checks final state.

## Serial Protocol

- `PING` returns `PONG`.
- `MODEL?` emits `VOICE_MODEL wake_engine=WakeNet(serial_sim) command_engine=MultiNet(serial_sim)`.
- `COMMANDS?` emits the current command table.
- `WAKE:<word>` simulates a WakeNet wake-word event.
- `CMD:<id-or-phrase>` simulates a MultiNet command recognition result.
- `ADDCMD:<id>:<phrase>:<action>` adds a runtime command.
- `MODCMD:<id>:<phrase>:<action>` modifies a runtime command.
- `DELCMD:<id>` disables a runtime command.
- `MODE:SINGLE` and `MODE:CONTINUOUS` switch recognition behavior.
- `PAGE:HOME`, `PAGE:COMMANDS`, `PAGE:STATE`, and `PAGE:LOG` switch pages.
- `STATE?` emits `VOICE_STATE`.

## Acceptance Gates

- Compile: `make offline-voice-build`
- Serial:
  - `VOICE_READY display=1 touch=1`
  - `VOICE_MODEL ... WakeNet ... MultiNet ...`
  - pre-wake `VOICE_REJECT reason=not_awake`
  - wake `VOICE_WAKE engine=WakeNet`
  - command `VOICE_CMD engine=MultiNet`
  - action `VOICE_ACTION action=LIGHT:ON`
  - runtime command `VOICE_COMMAND_ADDED id=FOCUS`
  - runtime command `VOICE_COMMAND_MODIFIED id=FOCUS`
  - runtime command `VOICE_COMMAND_DELETED id=FOCUS`
  - final `VOICE_STATE ... mode=CONTINUOUS`
- Visual: optional OCR sees `OK` on the AMOLED.

## Notes

- This is not yet a real ESP-SR audio pipeline. It is the deterministic control-plane gate that should remain after ES7210 microphone frames and ESP-SR models are wired in.
- Do not run microphone stimulus or speaker tests late at night. This harness is safe because it uses serial-only WakeNet/MultiNet simulation.

## Verified Locally

- `make offline-voice-build`: passed with `439255 bytes` program storage and `24192 bytes` dynamic memory.
- `SKIP_BUILD=1 make offline-voice-smoke`: uploaded to `/dev/cu.usbmodem83101` and validated pre-wake rejection, WakeNet/MultiNet serial simulation, runtime command add/modify/delete, continuous mode, sleep/wake, and light state.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target offline-voice --skip-build --per-target-timeout 240 --max-failures 1"`: passed with summary `.logs/hardware-smoke-suite/20260614-055754/summary.json`.
- Observed summary: `offline_voice_summary states=3 page_flow=COMMANDS,STATE,LOG,HOME commands=5 enabled=4 recognized=6 rejected=2 actions=6 mode=CONTINUOUS light=0 asleep=0`.
