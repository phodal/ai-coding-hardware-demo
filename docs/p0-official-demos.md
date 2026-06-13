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
- `make official-coverage` is read-only. It reports build artifacts, source presence, audio quiet-marker readiness, and existing physical smoke logs for every official demo without uploading or using audio devices.
- `make official-smoke DEMO=<id>` uploads to the connected board and captures serial output under `.logs/`.
- Vendor example folders are staged into `.arduino-build/official-sketches/<id>` before compilation because several official `.ino` filenames do not match their parent folder names, which `arduino-cli` requires.
- Visual proof for display-oriented demos can be layered with `make camera-aligner` and `make visual-smoke`, but vendor demos are intentionally kept unmodified in this lane.
- Audio demos need real audio stimulus or audible output checks in addition to serial matching.

## Verified Locally

- `make official-demos`: listed all 7 manifest rows.
- `make official-build DEMO=01-helloworld`: passed on the current Arduino CLI setup.
- `make official-build-all`: passed for all 7 Arduino examples on the current Arduino CLI setup.
- `make official-audio-preflight`: passed for `06-es7210-audio-in` and `07-es8311-audio-out`, with `official_audio_preflight_summary demos=2 failed=0 destructive=0 audio=0`.
- `make official-coverage`: passed read-only audit with `official_coverage_summary demos=7 built=7 physical_smoke=1 missing_physical=6 audio_demos=2 audio_quiet_ready=2 destructive=0 audio=0`.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh official-demo /Users/phodal/hardware/arduino coverage`: passed the same read-only audit through the global Skill helper.
- `SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `loop`.
- Latest smoke log: `.logs/official-01-helloworld-20260613-222514.log`.
- `make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target official-demos --allow-conditional --per-target-timeout 420 --max-failures 1"`: built, uploaded, and passed the default `01-helloworld` official display/serial baseline on `/dev/cu.usbmodem83101`.
- Latest suite summary: `.logs/hardware-smoke-suite/20260614-050454/summary.json`.
- Latest suite target log: `.logs/hardware-smoke-suite/20260614-050454/official-demos.log`.
- Latest suite serial log: `.logs/hardware-smoke-suite/20260614-050454/official-demos/official-01-helloworld-20260614-050707.log`.
- Latest suite build size: sketch `411067` bytes, globals `22896` bytes.
