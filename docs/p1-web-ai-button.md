# P1 Web AI Button

## Purpose

`sketches/web_ai_button` turns the board into a direct Wi-Fi client for a local Mac HTTP AI trigger server. The AMOLED shows `Qoder` above a large `ASK AI` button; tapping it makes the ESP32-S3 call the computer's webserver and renders the returned text on the screen.

This is the first board-to-computer AI trigger path. It intentionally avoids microphone and speaker hardware: touch plus HTTP proves the control plane before any audio UX is added.

## Commands

```bash
make local-ai-server
make web-ai-button-build
make web-ai-button-upload
make web-ai-button-smoke
WEB_AI_BUTTON_VISUAL_SMOKE=1 make web-ai-button-smoke
```

`make local-ai-server` starts `scripts/local-ai-webserver.py` on `0.0.0.0:8787` by default. The server accepts `POST /ask` or `POST /trigger` with JSON like:

```json
{"question":"touch button","source":"esp32-web-ai-button"}
```

It returns JSON with `text` and `response`. Default mode is `mock` and returns `Qoder OK from Mac`. Set `WEB_AI_SERVER_MODE=command` plus `AI_TRIGGER_COMMAND='...'` when the local server should call a real desktop AI command. The prompt is passed on stdin and through `AI_TRIGGER_PROMPT`.

`make web-ai-button-smoke` starts the local server, uploads `sketches/web_ai_button`, sends Wi-Fi credentials from the ignored `.env` file over serial, configures the board endpoint to the Mac LAN IP, triggers one request over serial, and verifies `WEB_AI_RESPONSE status=ok`.

For manual tapping after the smoke, keep the Mac server alive:

```bash
WEB_AI_KEEP_SERVER=1 SKIP_BUILD=1 make web-ai-button-smoke
```

Without `WEB_AI_KEEP_SERVER=1`, the smoke intentionally shuts down its temporary webserver when the automation exits.

## Local Configuration

Store Wi-Fi credentials only in `.env`:

```bash
WIFI_TEST_SSID='...'
WIFI_TEST_PASSWORD='...'
```

Optional variables:

```bash
WEB_AI_SERVER_PORT=8787
WEB_AI_HOST_IP=192.168.x.x
WEB_AI_SERVER_MODE=mock
WEB_AI_QUESTION='touch button'
WEB_AI_EXPECT='AI OK'
WEB_AI_KEEP_SERVER=1
```

Set `WEB_AI_HOST_IP` when the automatic macOS interface detection picks the wrong address. The board must be able to reach `http://$WEB_AI_HOST_IP:$WEB_AI_SERVER_PORT/ask` from the Wi-Fi network.

## Serial Contract

The board accepts:

- `PING`
- `STATE?`
- `CONFIG:<ssid>,<password>,<endpoint>`
- `TRIGGER`
- `TRIGGER:<prompt>`

The checker redacts credentials when printing the `CONFIG` command.

The board emits:

- `WEB_AI_READY display=... touch=... wifi=0`
- `WEB_AI_TOUCH_READY model=... points=...`
- `WEB_AI_WIFI status=ok connected=1 rssi=... ip=...`
- `WEB_AI_TRIGGER source=... count=... prompt_chars=...`
- `WEB_AI_RESPONSE status=ok code=200 chars=... text=...`
- `WEB_AI_STATE display=... touch=... wifi=... triggers=... touches=... ip=...`

## Acceptance

`make web-ai-button-smoke` passes when:

- the local HTTP server answers `/health`
- the sketch uploads successfully
- the board reports display and touch readiness
- Wi-Fi joins with credentials from `.env`
- serial `TRIGGER` reaches the local HTTP server
- the board emits `WEB_AI_RESPONSE status=ok`
- the returned text contains `WEB_AI_EXPECT`, default `Qoder OK`

Manual validation is the same runtime path: leave the local server running, tap the `ASK AI` button on the AMOLED, and watch the returned text update on the screen.

## Verified Locally

- `make web-ai-button-build`: passed with `1136687 bytes` program storage and `47224 bytes` dynamic memory.
- `SKIP_BUILD=1 WEB_AI_KEEP_SERVER=1 make web-ai-button-smoke`: uploaded to `/dev/cu.usbmodem83101`, started the local mock AI server, configured the board endpoint to `http://<mac-lan-ip>:8787/ask`, joined Wi-Fi with credentials from `.env`, reached `WEB_AI_RESPONSE status=ok code=200 text=Qoder OK from Mac`, and reported `web_ai_button_summary connected=1 ip=<esp32-lan-ip> triggers=1 touch=1`.
- `WEB_AI_KEEP_SERVER=1` was verified after the smoke: the detached server process was still running and `GET /health` returned HTTP 200.
- `WEB_AI_KEEP_SERVER=1 WEB_AI_BUTTON_VISUAL_SMOKE=1 OCR_ROTATE=180 make web-ai-button-smoke` saved the Qoder screen at `docs/evidence/web-ai-button-qoder-20260614-145545/camera-ocr-20260614-145545.jpg`, but exact OCR remained partial: Vision read the large `OK` marker as `Bol` in this camera position, so the visual command exited non-zero after the functional serial/HTTP checks passed.
- Evidence pack: `docs/evidence/web-ai-button-qoder-20260614-145545/summary.md`.
- A real pre-config tap was captured before this guard existed and returned `wifi_missing`; the current firmware now ignores pre-config button taps with `WEB_AI_TOUCH_IGNORED reason=not_ready` instead of treating them as failed AI requests. Touch remains wired to the same `triggerAi()` path after Wi-Fi and endpoint configuration.

## Notes

Do not commit SSIDs, passwords, local IPs, or AI command credentials. Keep the default server in mock mode for repeatable automation, and use command mode only for supervised local experiments.
