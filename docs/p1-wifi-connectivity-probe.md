# P1 Wi-Fi Connectivity Probe

## Purpose

`sketches/wifi_connectivity_probe` validates the ESP32-S3 Wi-Fi radio, serial control path, and AMOLED status rendering without requiring stored network credentials.

This probe moves the Cloud AI terminal, desktop widget, and IoT control panel toward real network operation while keeping the default smoke safe for shared or unknown Wi-Fi environments.

## Commands

```bash
make wifi-connectivity-build
make wifi-connectivity-smoke
WIFI_MIN_NETWORKS=1 make wifi-connectivity-smoke
WIFI_TEST_SSID="..." WIFI_TEST_PASSWORD="..." make wifi-connectivity-smoke
WIFI_CONNECTIVITY_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make wifi-connectivity-smoke
```

Default validation scans for nearby APs only. It does not print SSID names and does not require or persist credentials.

`WIFI_TEST_SSID` and `WIFI_TEST_PASSWORD` enable an optional join check. The host checker redacts the `JOIN` command in its own log, but the values still exist in the process environment while the command runs.

## Serial Contract

The board emits:

- `WIFI_READY display=1 radio=1`
- `WIFI_STATE display=... radio=... connected=... scan_count=... last_count=... best_rssi=... ip=...`
- `WIFI_AP index=... rssi=... channel=... enc=...`
- `WIFI_SCAN status=ok source=... count=... best_rssi=... elapsed_ms=... scan_count=...`
- `WIFI_JOIN status=ok connected=1 rssi=... ip=...` when optional join succeeds

The board accepts:

- `PING`
- `STATUS?`
- `SCAN`
- `JOIN:<ssid>,<password>`
- `DISCONNECT`

## Acceptance

`make wifi-connectivity-smoke` passes when:

- display and Wi-Fi radio initialization are visible over serial
- `PING` returns `PONG`
- a Wi-Fi scan completes with `status=ok`
- scan count is at least `WIFI_MIN_NETWORKS`, default `0`
- optional join connects and reports an IP when credentials are supplied

## Notes

Do not hard-code SSID or password into Arduino source, docs, or committed scripts. Use the serial `JOIN` path for supervised local testing and keep the default skill-facing smoke scan-only.

## Verified Locally

- `make wifi-connectivity-build`: passed.
- `SKIP_BUILD=1 make wifi-connectivity-smoke`: uploaded to `/dev/cu.usbmodem83101`, completed `PING`/`PONG`, serial scan, and status checks; scan count was 10, best RSSI was -67 dBm, and no SSID names were printed.
- `skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh wifi-connectivity /Users/phodal/hardware/arduino check --port /dev/cu.usbmodem83101 --seconds 1`: passed against the flashed sketch.
- `/Users/phodal/.codex/skills/waveshare-esp32s3-amoled/scripts/waveshare-arduino-cli.sh wifi-connectivity /Users/phodal/hardware/arduino check --port /dev/cu.usbmodem83101 --seconds 1`: passed against the flashed sketch.
