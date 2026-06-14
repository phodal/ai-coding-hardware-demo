# Web AI Button Evidence 20260614-124803

This evidence pack records the local Mac webserver plus ESP32-S3 Wi-Fi AI button validation chain.

## Result

- Build: passed
- Upload: passed
- Touch controller: ready
- Wi-Fi join: passed
- Local HTTP AI trigger: passed
- Camera OCR: passed
- Destructive: 0
- Audio: 0

## Serial Evidence

```text
WEB_AI_WIFI status=ok connected=1 rssi=-72 ip=192.168.31.65
WEB_AI_TRIGGER source=serial count=1 prompt_chars=12
WEB_AI_RESPONSE status=ok code=200 chars=14 text=AI OK from Mac
WEB_AI_STATE display=1 touch=1 wifi=1 triggers=1 touches=0 ip=192.168.31.65
web_ai_button_summary connected=1 ip=192.168.31.65 triggers=1 touch=1 expect='AI OK'
```

## Camera OCR

The board was left on the AI response screen after the passing smoke. Camera OCR was then run with:

```bash
OCR_EXPECTED=AI OCR_ROTATE=180 LOG_DIR=.logs/web-ai-button-visual ./scripts/camera-ocr.sh
```

OCR output included:

```text
WEB AI
ASK AI
WEB AI
ASK AI
```

## Artifacts

- Raw camera image: `camera-ocr-20260614-124803.jpg`
- Processed OCR image: `camera-ocr-20260614-124803.processed.png`
- OCR text: `camera-ocr-20260614-124803.txt`
- Local server log: `server.log`

## Interpretation

The automated smoke proves the board can join Wi-Fi, reach the Mac HTTP server, trigger the local AI endpoint, and display the response. The touch controller is ready and the same trigger path is bound to the on-screen `ASK AI` button; a supervised human tap remains the only missing physical-button event evidence.
