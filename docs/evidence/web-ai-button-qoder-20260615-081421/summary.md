# Web AI Button Qoder Evidence 20260615-081421

This evidence pack records the Qoder-branded local Mac webserver plus ESP32-S3 Wi-Fi AI button validation chain with a camera OCR pass.

## Result

- Build: passed
- Upload: passed
- Touch controller: ready
- Wi-Fi join: passed
- Local HTTP AI trigger: passed
- Local server keepalive: passed
- Camera capture: passed
- Camera OCR: passed
- Destructive: 0
- Audio: 0

## Serial Evidence

```text
WEB_AI_WIFI status=ok connected=1 rssi=-72 ip=<esp32-lan-ip>
WEB_AI_TRIGGER source=serial count=1 prompt_chars=12
WEB_AI_RESPONSE status=ok code=200 chars=17 text=Qoder OK from Mac
WEB_AI_STATE display=1 touch=1 wifi=1 triggers=1 touches=0 ip=<esp32-lan-ip>
web_ai_button_summary connected=1 ip=<esp32-lan-ip> triggers=1 touch=1 expect='Qoder OK'
web_ai_server_kept_alive pid=94959 log=/Users/phodal/hardware/arduino/.logs/web-ai-server.log endpoint=http://<mac-lan-ip>:8787/ask
```

## Camera OCR

The success screen uses a low-brightness black background with large `Qoder` and `OK` text so the camera/OCR gate does not depend on overexposed green-button text.

OCR was run with:

```bash
WEB_AI_KEEP_SERVER=1 WEB_AI_BUTTON_VISUAL_SMOKE=1 OCR_ROTATE=180 make web-ai-button-smoke
```

OCR output included:

```text
AI OK
Qoder
OK
```

## Artifacts

- Raw camera image: `camera-ocr-20260615-081421.jpg`
- Upright preview: `qoder-ok-upright.jpg`
- Processed OCR image: `camera-ocr-20260615-081421.processed.png`
- OCR text: `camera-ocr-20260615-081421.txt`
- Local server log: `server.log`

## Interpretation

The automated smoke proves the board can join Wi-Fi, reach the Mac HTTP server, render the Qoder success screen, and pass camera OCR on the stable `OK` marker. This is still an external/local-network lane because it depends on ignored `.env` Wi-Fi credentials and a reachable Mac HTTP endpoint.
