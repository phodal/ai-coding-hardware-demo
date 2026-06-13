# P1 LVGL Visual Agent

The `lvgl_visual_agent` sketch is the first repo-owned LVGL visual-agent surface for the Waveshare ESP32-S3-Touch-AMOLED-1.75C. Unlike the earlier Arduino_GFX control panels, this sketch initializes LVGL, registers a CO5300 display flush driver, registers CST92xx touch input, and builds a real LVGL tabview with chat, cards, and settings pages.

## What It Proves

- LVGL can initialize on the board with the vendor `lv_conf.h` and Arduino-v3.3.5 libraries.
- The AMOLED can render LVGL widgets through the `Arduino_CO5300` flush path.
- The CST9217/CST92xx touch controller can be registered as an LVGL pointer input.
- A host relay can drive a visual agent surface over serial: chat bubbles, agent thoughts, cards, and settings.

## Commands

```bash
make lvgl-visual-agent-build
make lvgl-visual-agent-smoke
LVGL_VISUAL_AGENT_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make lvgl-visual-agent-smoke
```

The smoke script uploads the sketch, waits for `VIS_READY`, validates LVGL capabilities, drives page changes, sends chat/card/settings events, and checks final serial state.

## Serial Protocol

- `PING` returns `PONG`.
- `CAPS?` emits `VIS_CAPS` with the LVGL version and widget surface.
- `PAGE:CHAT`, `PAGE:CARDS`, and `PAGE:SETTINGS` switch LVGL tabs.
- `CHAT:<text>` appends the current chat bubble text.
- `AGENT:THINK:<text>` updates the agent thought panel.
- `CARD:<id>:<state>:<title>` updates the card flow.
- `SETTING:<key>:<value>` updates the settings page.
- `STATE?` emits `VIS_STATE`.

## Acceptance Gates

- Compile: `make lvgl-visual-agent-build`
- Serial:
  - `VIS_READY display=1 touch=1 lvgl=1`
  - `VIS_CAPS ... widgets=tabview,labels,cards,settings`
  - `VIS_CHAT count=1`
  - `VIS_AGENT event=think`
  - two `VIS_CARD` updates
  - two `VIS_SETTING` updates
  - final `VIS_STATE` with nonzero chat/cards/settings/agent counters
- Visual: optional OCR sees `OK` on the AMOLED.

## Notes

- This is the preferred repo-owned LVGL app surface. The official `05-lvgl-widgets` demo remains the vendor baseline, while this sketch validates an agent-specific workflow under automation.
- This path is safe for late-night validation because it does not play audio or use the host microphone.
