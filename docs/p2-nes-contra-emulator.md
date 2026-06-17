# P2 NES Contra Emulator

This lane starts the full Contra path for the Waveshare ESP32-S3-Touch-AMOLED-1.75C by creating a NES emulator integration surface. The current implementation is a diagnostic scaffold: it initializes the CO5300 AMOLED path, probes CST92xx touch, renders a visible runner animation strip, exposes a `NES_CONTRA_*` serial protocol, and reports that the target ROM is still missing. It does not vendor an emulator core or commit Contra ROM bytes.

The architecture decision is recorded in `/Users/phodal/hardware/arduino/docs/adr/0001-nes-contra-emulator-path.md`.

## Commands

```bash
make nes-contra-preflight
make nes-contra-build
make nes-contra-smoke
NES_CONTRA_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make nes-contra-smoke
```

`make nes-contra-preflight` inspects `/Users/phodal/hardware/nes-contra-us`, reports whether `/Users/phodal/hardware/nes-contra-us/baserom.nes` and `/Users/phodal/hardware/nes-contra-us/contra.nes` exist, checks the cc65 tools, and parses the iNES header when a ROM is present. In the current local state it is expected to report `status=missing-rom`, because the legally supplied ROM is not present.

`make nes-contra-smoke` uploads `/Users/phodal/hardware/arduino/sketches/nes_contra_emulator` and verifies the diagnostic serial protocol. The screen shows a large `OK` marker plus a small diagnostic runner moving across a bordered strip. This is a hardware scaffold gate, not proof that Contra gameplay is running.

## Serial Protocol

- `PING` returns `PONG`.
- `CAPS?` emits `NES_CONTRA_CAPS` with display, input, target mapper, and audio status.
- `ROM?` emits `NES_CONTRA_ROM`; the scaffold currently reports `status=missing`.
- `INPUT:<buttons>` records deterministic input for future emulator injection.
- `STATE?` and `FRAME?` emit `NES_CONTRA_STATE` / `NES_CONTRA_FRAME`.
- `READY?` re-emits `NES_CONTRA_READY`.

## Acceptance Gates

- Preflight: `make nes-contra-preflight` prints source, ROM, iNES, and cc65 toolchain state without modifying tracked files.
- Compile: `make nes-contra-build`
- Serial scaffold: `make nes-contra-smoke`
  - board emits `NES_CONTRA_READY display=1 mode=diagnostic target_mapper=2`
  - `PING`, `CAPS?`, `ROM?`, `INPUT:A`, and `STATE?` are accepted
  - frame count advances after boot
- Visual: optional OCR sees the stable large `OK` marker before real game pixels are used as evidence. The moving runner strip is a human-visible animation indicator, not an OCR acceptance marker.

## Boundaries

- Do not commit `/Users/phodal/hardware/nes-contra-us/baserom.nes`, `/Users/phodal/hardware/nes-contra-us/contra.nes`, or generated ROM headers.
- Do not vendor GPL or unknown-license emulator code until a follow-up license decision is recorded.
- Do not claim full Contra runtime support until the emulator core boots a Mapper 2 ROM and serial evidence reports nonzero emulator frames.
- Do not claim audio support until ES8311 physical output evidence exists.

## Next Steps

1. Add ignored generated ROM header or partition tooling after the local legal ROM exists.
2. Pick an emulator core after license review and isolate it behind display, input, ROM, and audio adapters.
3. Replace diagnostic runner/frame progress with emulator frame progress while keeping the same serial protocol.
4. Add ES8311 audio only after silent display/input gates are stable.

## Verified Locally

- `make nes-contra-preflight`: reported `/Users/phodal/hardware/nes-contra-us` exists, `baserom.nes` and `contra.nes` are missing, and `ca65`, `ld65`, `cc65`, and `cl65` are not installed. Summary: `nes_contra_preflight_summary status=missing-rom source=1 baserom=0 rom=0 tools_missing=ca65,ld65,cc65,cl65 issues=none`.
- `make nes-contra-build`: compiled `sketches/nes_contra_emulator` with `433623 bytes` program storage and `23072 bytes` dynamic memory.
- `make nes-contra-smoke`: first retry at the default 921600 upload speed stopped during flashing with `The chip stopped responding`; the smoke wrapper now defaults this lane to `NES_CONTRA_UPLOAD_SPEED=460800`.
- Successful smoke command: `SKIP_BUILD=1 make nes-contra-smoke`.
- Successful serial summary after adding the diagnostic runner animation: `nes_contra_summary mode=diagnostic target_mapper=2 rom=missing display=1 touch=1 frames=180 input_events=1 touch_events=0`.
- Serial evidence: `.logs/nes-contra-20260617-083958/serial-check.log`.
