# ADR 0001: Run Contra Through a NES Emulator Port

## Status

Accepted for planning.

## Context

The target hardware workspace is `/Users/phodal/hardware/arduino`, built around the Waveshare ESP32-S3-Touch-AMOLED-1.75C. The current local baseline is Arduino CLI with `esp32:esp32@3.3.5`, the generic ESP32-S3 FQBN using `FlashSize=16M`, the CO5300 QSPI AMOLED display path, CST9217/CST92xx touch input, QMI8658 IMU, ES7210 audio input, and ES8311 audio output. The board is already validated through repo-owned build, serial, audio, and camera/OCR lanes such as `make lvgl-visual-agent-smoke`, `make speaker-output-smoke`, and `make hardware-smoke-suite`.

The Contra source under `/Users/phodal/hardware/nes-contra-us` is an annotated disassembly and rebuild project, not an ESP32 game runtime. It requires a user-supplied `/Users/phodal/hardware/nes-contra-us/baserom.nes` and the cc65 toolchain before it can rebuild `/Users/phodal/hardware/nes-contra-us/contra.nes`. The local checkout currently has no `baserom.nes`, and `ca65`, `ld65`, `cc65`, and `cl65` are not installed.

Contra US is a NES title using iNES Mapper 002 / UxROM, 8 x 16 KiB PRG banks, CHR-RAM, NES PPU tile/nametable/sprite rendering, controller polling, and NES APU audio. Reimplementing the entire game natively from the disassembly would require translating substantial 6502 game, PPU, collision, enemy, weapon, and audio behavior into C++.

External prior art makes the emulator route plausible on ESP32-class hardware:

- Espressif's `esp32-nesemu` ports Nofrendo to ESP32, runs close to full speed, but lacks sound and uses an ILI9341 SPI display path: https://github.com/espressif/esp32-nesemu
- `CornN64/nesemu` is an Arduino ESP32 NES emulator with LCD, audio, SD card, and controller support: https://github.com/CornN64/nesemu
- `derdacavga/Esp32-S3-nes-emulator-by-DSN` targets ESP32-S3 with Nofrendo-derived code, I2S audio, ST7789 display, SD card ROMs, and 8-button input: https://github.com/derdacavga/Esp32-S3-nes-emulator-by-DSN
- `Shim06/Anemoia-ESP32` reports native NES speed with full audio and lists Contra as a Mapper 2 benchmark: https://github.com/Shim06/Anemoia-ESP32
- Waveshare documents the 1.75C hardware as ESP32-S3R8 with 8 MB PSRAM, 466 x 466 AMOLED, CO5300 over QSPI, CST9217 over I2C, QMI8658 IMU, audio codec, microphone, speaker, and onboard storage resources: https://docs.waveshare.com/ESP32-S3-Touch-AMOLED-1.75C

## Decision

Implement the full Contra path as a NES emulator lane for `/Users/phodal/hardware/arduino`, not as a native Contra rewrite.

The first implementation target is:

- New repo lane id: `nes-contra-emulator`
- Board sketch path: `/Users/phodal/hardware/arduino/sketches/nes_contra_emulator`
- Build output path: `/Users/phodal/hardware/arduino/.arduino-build/nes_contra_emulator`
- Documentation path: `/Users/phodal/hardware/arduino/docs/p2-nes-contra-emulator.md`
- ADR path: `/Users/phodal/hardware/arduino/docs/adr/0001-nes-contra-emulator-path.md`
- Local Contra source path: `/Users/phodal/hardware/nes-contra-us`
- Local ROM input path, ignored by git: `/Users/phodal/hardware/nes-contra-us/baserom.nes`
- Local rebuilt ROM path, ignored by git: `/Users/phodal/hardware/nes-contra-us/contra.nes`
- Generated firmware-side ROM header path, ignored or generated during build: `/Users/phodal/hardware/arduino/.generated/nes_contra/contra_rom.h`

The emulator core must be treated as a replaceable third-party component until licensing and integration cost are confirmed. The first spike should compare Nofrendo-derived options and Anemoia-style architecture, then choose one core based on Mapper 2 support, Arduino/ESP-IDF integration effort, audio path, license compatibility, and display hook clarity. Do not vendor GPL emulator code into this repository without an explicit follow-up licensing decision.

The initial device target is single-ROM Contra, not a generic ROM browser. ROM bytes must not be committed. The build flow should either read a local legally supplied `.nes` file and generate an ignored header or flash it to an ignored data partition.

## Implementation Path

1. Add a no-hardware preflight script at `/Users/phodal/hardware/arduino/scripts/nes-contra-preflight.py`.
   It should check `/Users/phodal/hardware/nes-contra-us`, detect `baserom.nes`, report whether cc65 tools are installed, identify or build `contra.nes` when legal inputs exist, parse the iNES header, and fail unless Mapper 2 / UxROM is detected.

2. Add a board sketch under `/Users/phodal/hardware/arduino/sketches/nes_contra_emulator`.
   It should initialize the existing CO5300 QSPI display path from local `pin_config.h`, expose a minimal serial protocol, and boot into a visible diagnostic screen before emulator execution.

3. Add an emulator display adapter.
   The NES frame is 256 x 240. Render it centered into the 466 x 466 round AMOLED viewport, initially at integer scale 1 with optional 2x crop experiments only after correctness is proven. Use dirty rectangles or line/tile batching only after a full-frame baseline is measured.

4. Add input adapters in this order:
   serial commands for deterministic smoke tests, then touch overlay buttons for A/B/Start/Select/D-pad, then optional IMU or external controller experiments. The acceptance path must not depend on a human tap until a supervised physical-input gate is added.

5. Add audio after silent visual and input gates pass.
   Start with mute or simple frame pacing. Then route emulator PCM/APU output into the existing ES8311/I2S path and validate with the same physical-audio discipline used by `/Users/phodal/hardware/arduino/docs/p0-speaker-output-probe.md`.

6. Add Makefile targets and feature-matrix metadata:
   `nes-contra-preflight`, `nes-contra-build`, `nes-contra-smoke`, and optionally `nes-contra-visual-smoke`. Keep uploads serialized through the existing scripts and use `.arduino-build/nes_contra_emulator`.

7. Add smoke behavior:
   the serial smoke should prove boot, ROM header acceptance, Mapper 2 support, frame loop progress, input injection, and a stable diagnostic line such as `NES_CONTRA_READY mapper=2 frames=<n>`.
   The visual smoke should show a large stable `NES OK` or `CONTRA OK` marker before trying OCR on real game pixels.

## Consequences

This path preserves the original Contra runtime semantics better than a native rewrite and lets the disassembly project remain the ROM/source reference. It also aligns with existing ESP32 NES emulator prior art and avoids translating large 6502 game systems by hand.

The tradeoff is integration complexity. The project must adapt display, frame pacing, input, ROM storage, and ES8311 audio to this specific Waveshare board. Existing emulator projects mostly assume ILI9341/ST7789/SPI displays, SD cards, physical buttons, or different audio hardware.

The route also introduces licensing and ROM handling constraints. GPL emulator cores may impose distribution obligations, and Contra ROM bytes must remain user-supplied and ignored by git.

## Rejected Alternatives

- Native Contra rewrite from `/Users/phodal/hardware/nes-contra-us`: rejected for the full path because it would require reimplementing core game behavior, PPU semantics, enemies, weapons, collision, scroll, and APU audio manually.
- Contra-style demo using extracted PNG sprites: useful as a separate quick visual demo, but rejected for this ADR because it is not the full Contra path.
- Generic multi-ROM handheld first: rejected for the first milestone because it adds SD/browser/menu scope before Contra Mapper 2 and the board display/audio/input adapters are proven.

## Acceptance Criteria

- `make nes-contra-preflight` reports the exact local ROM/toolchain state without modifying tracked files.
- `make nes-contra-build` compiles the board sketch with the existing ESP32-S3 FQBN and dedicated build path.
- `make nes-contra-smoke` uploads serially, proves emulator boot/control flow over raw serial, and writes evidence under `/Users/phodal/hardware/arduino/.logs/`.
- `NES_CONTRA_READY` includes Mapper 2 acceptance and nonzero frame progress.
- Optional visual smoke first proves a stable OCR marker; real game OCR is supporting evidence only.
- Audio is not claimed until ES8311 physical output evidence exists.

## Open Questions

- Which emulator core should be integrated after license review: Nofrendo-derived code, Anemoia-style code, or a smaller Mapper 2-only core?
- Should the ROM be compiled into firmware as an ignored generated header or stored in a flash/TF partition?
- Should first playable input be touch overlay, external buttons through the 8-pin header, BLE HID, or serial-only automation plus supervised touch?
