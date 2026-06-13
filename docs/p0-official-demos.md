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
```

Use `scripts/official-demo.sh list` for the full manifest. Each row in `config/official-demos.tsv` records the demo id, functional category, vendor sketch directory, and expected serial text for smoke validation.

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
- `make official-smoke DEMO=<id>` uploads to the connected board and captures serial output under `.logs/`.
- Vendor example folders are staged into `.arduino-build/official-sketches/<id>` before compilation because several official `.ino` filenames do not match their parent folder names, which `arduino-cli` requires.
- Visual proof for display-oriented demos can be layered with `make camera-aligner` and `make visual-smoke`, but vendor demos are intentionally kept unmodified in this lane.

## Verified Locally

- `make official-build DEMO=01-helloworld`: passed.
- `make official-build-all`: passed for all 7 Arduino examples.
- `SMOKE_SECONDS=8 make official-smoke DEMO=01-helloworld`: uploaded to `/dev/cu.usbmodem83101` and matched serial text `loop`.
- Latest smoke log: `.logs/official-01-helloworld-20260613-222514.log`.
