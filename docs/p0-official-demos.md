# P0 Official Demo Bring-up

This is the acceptance ladder for the Waveshare official Arduino examples. The goal is to prove the board, drivers, and toolchain before building AI features on top.

Source references:

- Waveshare Arduino docs list the example package, bundled libraries, and demo coverage.
- The local vendor package is selected by `WAVESHARE_VENDOR_DIR`; by default this repo uses `/Users/phodal/Downloads/ESP32-S3-Touch-AMOLED-1.75C-main` when present.

## Commands

```bash
make official-demos
make official-build DEMO=01-helloworld
make official-smoke DEMO=01-helloworld
make official-build-all
make official-audio-preflight
make official-audio-physical-plan
ALLOW_AUDIO=1 make official-audio-physical-smoke
ALLOW_AUDIO=1 OFFICIAL_AUDIO_OUTPUT_CONFIRM=heard make official-audio-physical-smoke
make official-coverage
```

Use `scripts/official-demo.sh list` for the full manifest. Each row in `config/official-demos.tsv` records the demo id, functional category, vendor sketch directory, and expected serial text for smoke validation. The `path` action prints the staged sketch directory used by `arduino-cli`:

```bash
scripts/official-demo.sh path 01-helloworld
```

## P0 Coverage

| Demo | Covers | Evidence |
| --- | --- | --- |
| `01-helloworld` | Display, GFX, base Arduino toolchain | Build plus runtime serial text `loop` |
| `02-ascii-table` | Display text layout | Build plus serial text `Arduino_GFX AsciiTable example` |
| `03-power-axp2101` | PMU, power data, LVGL | Build plus serial text `Setup done` |
| `04-imu-qmi8658` | IMU, LVGL chart | Build plus serial text `Read data now` |
| `05-lvgl-widgets` | LVGL widgets, touch input | Build plus serial text `Setup done` |
| `06-es7210-audio-in` | Microphone input, VAD | Build plus serial text `Speech detected` after audio stimulus |
| `07-es8311-audio-out` | Audio codec/output | Build plus serial text `[echo] Echo start` plus audible output |

## Notes

- `make official-build DEMO=<id>` is non-destructive and compiles only.
- `make official-build-all` compiles every manifest row serially and returns a non-zero exit code if any demo fails.
- `make official-audio-preflight` compiles only the official ES7210/ES8311 audio demos and checks source/serial markers without uploading firmware or using audio devices.
- `make official-audio-physical-plan` is safe at night. It prints the gated physical-audio plan for the official ES7210/ES8311 demos without uploading or using audio devices.
- `make official-audio-physical-smoke` is intentionally refused unless `ALLOW_AUDIO=1` is set. The ES7210 input path plays the configured host stimulus while serial capture is open; the ES8311 output path also requires `OFFICIAL_AUDIO_OUTPUT_CONFIRM=heard` after a supervised audible check.
- `make official-coverage` is read-only. It reports build artifacts, source presence, audio quiet-marker readiness, and existing physical smoke logs for every official demo without uploading or using audio devices.
- `make official-smoke DEMO=<id>` uploads to the connected board and captures serial output under `.logs/`.
- Official smoke capture uses `scripts/serial-capture.py` by default so the log is open before pulsing RTS reset; this is required for demos that print expected serial text only during `setup()`.
- Vendor example folders are staged into `.arduino-build/official-sketches/<id>` before compilation because several official `.ino` filenames do not match their parent folder names, which `arduino-cli` requires.
- Visual proof for display-oriented demos can be layered with `make camera-aligner` and `make visual-smoke`. Vendor source directories are not modified; automation-only changes are applied only to staged copies under `.arduino-build/official-sketches/<id>`.
- Audio demos need real audio stimulus or audible output checks in addition to serial matching.
- `03-power-axp2101` uses a staged-only `OFFICIAL_POWER_WIFI_TIMEOUT_MS` patch during automation. It still attempts the vendor Station Wi-Fi connection, but it continues to AP, PMU, and LVGL initialization after the timeout so the power demo can be physically smoked without local vendor credentials. This proves PMU/LVGL startup, not Station Wi-Fi success.

## Verified Locally

- `make official-demos`: listed all 7 manifest rows.
- `make official-build DEMO=01-helloworld`: passed on the current Arduino CLI setup.
- `make official-build-all`: passed for all 7 Arduino examples on the current Arduino CLI setup.
- `make official-audio-preflight`: passed for `06-es7210-audio-in` and `07-es8311-audio-out`, with `official_audio_preflight_summary demos=2 failed=0 destructive=0 audio=0`.
- `make official-audio-physical-plan`: passed without uploading or using audio devices and reported both official audio demos as gated by `ALLOW_AUDIO`.
- `make official-audio-physical-smoke` without `ALLOW_AUDIO=1`: refused with `official_audio_physical_smoke status=refused ... destructive=0 audio=0`.
- `make official-coverage`: passed read-only audit with `official_coverage_summary demos=7 built=7 physical_smoke=5 missing_physical=2 audio_demos=2 audio_quiet_ready=2 destructive=0 audio=0`.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh official-demo /Users/phodal/hardware/arduino coverage`: passed the same read-only audit through the global Skill helper.
- `SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `loop`.
- Latest smoke log: `.logs/official-01-helloworld-20260613-222514.log`.
- `SKIP_BUILD=1 SMOKE_SECONDS=8 make official-smoke DEMO=02-ascii-table`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `Arduino_GFX AsciiTable example`.
- Latest `02` smoke log: `.logs/official-02-ascii-table-20260614-064730.log`.
- `SKIP_BUILD=1 SMOKE_SECONDS=10 make official-smoke DEMO=04-imu-qmi8658`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `Read data now`; the log includes continuous `{ACCEL: ...}` samples around 0.96 g on Z.
- Latest `04` smoke log: `.logs/official-04-imu-qmi8658-20260614-064847.log`.
- `SKIP_BUILD=1 SMOKE_SECONDS=10 make official-smoke DEMO=05-lvgl-widgets`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `Setup done`; the log includes `Model :CST9217`.
- Latest `05` smoke log: `.logs/official-05-lvgl-widgets-20260614-064920.log`.
- `SKIP_BUILD=1 SMOKE_SECONDS=16 OFFICIAL_POWER_WIFI_TIMEOUT_MS=5000 make official-smoke DEMO=03-power-axp2101`: uploaded to `/dev/cu.usbmodem83101`, printed `OFFICIAL_POWER_WIFI_TIMEOUT continuing PMU/LVGL smoke`, started AP mode, initialized LVGL, and matched serial text `Setup done`.
- Latest `03` smoke log: `.logs/official-03-power-axp2101-20260614-072414.log`.
- Earlier unpatched `03` smoke failed at Station Wi-Fi connection before `Setup done`; failed log `.logs/official-03-power-axp2101-20260614-064803.log`.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target official-demos --allow-conditional --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed the default `01-helloworld` official display/serial baseline on `/dev/cu.usbmodem83101`.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-084339/summary.json`.
- Latest suite target log: `.logs/hardware-smoke-suite/20260614-084339/official-demos.log`.
- Latest suite serial log: `.logs/hardware-smoke-suite/20260614-084339/official-demos/official-01-helloworld-20260614-084516.log`.
- Latest suite build size: sketch `411067` bytes, globals `22896` bytes.
