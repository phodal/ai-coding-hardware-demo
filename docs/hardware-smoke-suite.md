# Hardware Smoke Suite

`scripts/hardware-smoke-suite.py` is the serialized runner for feature-level hardware smokes in `config/feature-matrix.tsv`.

It exists to keep board validation deterministic:

- It runs selected `make <smoke_target>` commands one at a time.
- It writes per-target logs and `summary.json` under `.logs/hardware-smoke-suite/<timestamp>/`.
- It defaults to non-audio lanes only: `audio_mode=none` and `audio_mode=non_audio_control`.
- It skips `conditional` and `required_external` lanes unless explicitly allowed.
- It only requires `--allow-audio` for smoke targets that use physical microphone or speaker hardware.
- It forces `*_VISUAL_SMOKE=0` by default so a suite run does not depend on camera framing. Use `--with-visual` only when the camera is positioned.
- Use `--skip-build` only when the relevant `.arduino-build/<name>` artifacts already exist. If upload reports a missing `*.partitions.bin`, rerun that target without `--skip-build`.

## Commands

```bash
make hardware-smoke-list
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--dry-run"
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target iot-panel --skip-build"
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--targets power-lifecycle,imu-interaction"
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target official-demos --allow-conditional"
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target xiaozhi-ai --allow-external"
```

Audio lanes require explicit opt-in:

```bash
make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target audio-front-end --allow-audio"
```

Do not run audio lanes late at night unless the user explicitly asks for them.

## Verified Locally

- `make hardware-smoke-list`: selected only `none` and `non_audio_control` lanes by default; skipped `audio`, `conditional`, and external lanes.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--dry-run"`: printed the default non-audio command plan without running hardware.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target iot-panel --skip-build --per-target-timeout 180"`: uploaded to `/dev/cu.usbmodem83101`, ran `iot-panel-relay-smoke`, and wrote `.logs/hardware-smoke-suite/20260614-043837/summary.json` with `passed=1 failed=0`.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target official-demos --allow-conditional --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed the default official `01-helloworld` display/serial baseline without running audio demos; summary `.logs/hardware-smoke-suite/20260614-050454/summary.json` has `passed=1 failed=0`.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target xiaozhi-ai --allow-external --per-target-timeout 180 --max-failures 1"`: ran the non-destructive XiaoZhi preflight without flashing firmware or using audio hardware; summary `.logs/hardware-smoke-suite/20260614-062838/summary.json` has `passed=1 failed=0` and records the `merged-binary.bin` SHA-256 plus `destructive=0 audio=0`.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh hardware-smoke-suite /Users/phodal/hardware/arduino --list`: passed through the repo Skill helper.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh hardware-smoke-suite /Users/phodal/hardware/arduino --list`: passed through the global Skill helper.
