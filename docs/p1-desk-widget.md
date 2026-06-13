# P1 Desk Widget

The `desk_widget` sketch is a serial-driven desktop AI widget surface for the Waveshare ESP32-S3-Touch-AMOLED-1.75C. It focuses on always-on display workflows that do not require audio: status lights, GitHub/CI alerts, a pomodoro timer, and short AI summaries.

## What It Proves

- The AMOLED can render a compact desk widget with multiple pages.
- The CST9217 touch controller initializes and can cycle pages when tapped.
- A host-side relay can push CI, GitHub, alert, timer, and AI-summary state over serial.
- Automation can validate the widget without network credentials or audio devices.

## Commands

```bash
make desk-widget-build
make desk-widget-smoke
DESK_WIDGET_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make desk-widget-smoke
```

The smoke script uploads the sketch, waits for `WIDGET_READY`, sends CI/GitHub/alert/timer/summary commands, and verifies `WIDGET_STATE` plus the serial page flow.

## Serial Protocol

- `PING` returns `PONG`.
- `PAGE:HOME`, `PAGE:STATUS`, `PAGE:TIMER`, and `PAGE:SUMMARY` switch pages.
- `WIDGET:CI:<OK|WARN|FAIL>[:label]` sets the CI status card.
- `WIDGET:GITHUB:<count>` sets the GitHub/notification count.
- `WIDGET:ALERT:<text>` increments the alert count and updates alert text.
- `TIMER:SET:<minutes>`, `TIMER:START`, `TIMER:PAUSE`, and `TIMER:RESET` control the pomodoro card.
- `WIDGET:SUMMARY:<text>` updates the AI summary card.
- `STATE?` emits `WIDGET_STATE`.

## Notes

This is a control-plane and UI slice. It does not require Wi-Fi credentials yet; a future host relay can translate GitHub, calendar, CI, or LLM events into the same serial protocol before moving the device to direct Wi-Fi integrations.
