# P1 Touch Status Probe

This slice validates the CST9217 touch controller path used by the official LVGL widgets demo without requiring a full LVGL app. The board displays `TOUCH OK`, emits controller status over serial, and optionally records touch coordinates when a human touches the screen.

## Commands

```bash
make touch-status-build
make touch-status-smoke
TOUCH_STATUS_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make touch-status-smoke
TOUCH_REQUIRE_EVENT=1 make touch-status-smoke
```

## Acceptance Gates

- Compile: `make touch-status-build`
- Serial:
  - `TOUCH_READY model=CST9217`
  - repeated `TOUCH_STATUS ... ready=1 model=CST9217`
- Visual: optional OCR sees `OK` on the AMOLED.
- Manual touch: optional `TOUCH_REQUIRE_EVENT=1` requires at least one `TOUCH_EVENT ... x=<n> y=<n>` during the smoke window.

## Local Evidence

Last successful controller-online smoke:

```text
touch_summary model=CST9217 support_points=1 status_lines=8 events=0 reported_events=0
OCR validation passed.
```

Camera artifacts:

```text
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260614-000801.jpg
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260614-000801.processed.png
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260614-000801.txt
```

Representative serial data:

```text
TOUCH_STATUS frame=200 ready=1 model=CST9217 events=0 int=1
```

## Notes

- The default smoke proves the controller is online, not that a physical touch was performed.
- Use `TOUCH_REQUIRE_EVENT=1` for a supervised manual touch pass.
- The probe uses Arduino_GFX directly to keep the validation narrow. LVGL touch integration remains covered by the official `05-lvgl-widgets` build path and can be promoted into an interactive dashboard later.
