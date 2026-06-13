# Agent Notes

Recoding changes to the AGENTS.md file for better organization and clarity.

## Hardware Verification Practices

- Keep each hardware lane scriptable from `make`; interactive IDE state is not enough evidence.
- Prefer a narrow compile/upload/smoke loop before adding abstractions. For this board, clean Arduino CLI builds with dedicated `.arduino-build/<name>` paths avoid cache collisions.
- Treat serial output and camera OCR as complementary evidence: serial proves firmware control flow, while camera OCR proves the AMOLED actually renders expected text.
- Keep destructive actions explicit. Firmware replacement commands should require a visible confirmation variable or `--yes`.
- Stage vendor sketches instead of editing vendor sources when Arduino CLI requires folder and `.ino` names to match.

## Current Challenges

- The installed ESP32 Arduino core has no dedicated 1.75C FQBN, so the repo pins a generic ESP32-S3 FQBN with explicit flash/PSRAM/USB options.
- `arduino-cli monitor` can open but capture no bytes on the local USB Serial/JTAG port; raw `stty` plus `cat` is the reliable serial path.
- Camera OCR is sensitive to orientation, focus, glare, and pixel font shape. Use `make camera-aligner` and keep validation text large and simple.
- Vision OCR can misread `AI OK` as `HI OK`; use serial to verify the full payload and OCR a stable subset such as `OK`.
- `pyserial` is not installed in the current Python, so host relay tools should use stdlib `termios` or document their dependency explicitly.
- ESP-IDF is not currently sourced in this shell, so XiaoZhi source builds can only be checked up to board configuration until `idf.py` is available.

## Cloud AI Terminal Direction

- The first self-developed terminal slice uses serial relay control before direct audio streaming. This validates display rendering and host/cloud protocol shape without blocking on ASR/TTS integration.
- The next hardware step is to move from mock/HTTP text responses to ES7210 microphone capture and ES8311 playback, reusing official audio demos as known-good references.

## Feature Push README Hook

- This repo uses `.githooks/pre-push`; install it with `make install-hooks` or `git config core.hooksPath .githooks`.
- When an outgoing push ref or commit subject includes `feat`, the hook must update the generated `README.md` section between `<!-- feat-push-readme:start -->` and `<!-- feat-push-readme:end -->`.
- Because a pre-push hook cannot add a newly modified `README.md` to the already prepared push, the hook intentionally stops that push after updating the file. Commit the README change, then push again.
- AI agents changing feature behavior should keep `README.md` current before committing, and should not remove the generated marker block unless they also replace the hook behavior.
