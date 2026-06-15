# Evidence Packs

This directory stores committed hardware evidence packs that are useful for articles, handoffs, and agent-to-agent verification.

Each `ok-qoder-*` pack is produced by:

```bash
make ok-qoder-evidence
```

Use `ALLOW_PARTIAL=1 make ok-qoder-evidence` only when you intentionally want to preserve a failed or partial run for debugging. The screen is expected to show large `Qoder` branding; OCR gates on the stable `OK` marker while the raw camera image preserves the full visual state. A full visual claim requires:

- `summary.md` reports build, smoke, serial, and camera OCR as passed
- `summary.json` reports the same statuses for agents and scripts
- `camera-ocr-*.jpg` exists as the raw camera frame
- `camera-ocr-*.processed.png` exists as the OCR input image
- `camera-ocr-*.txt` contains the expected marker

Serial logs prove firmware control flow. Camera/OCR artifacts prove the AMOLED rendered the expected screen.

Current passing baseline: `ok-qoder-20260614-120532`. It records `display_rotation=0` and `ocr_rotation=180` for the current desk camera mount.

`web-ai-button-*` packs record the Mac local webserver plus ESP32-S3 Wi-Fi AI button lane. `web-ai-button-qoder-20260615-081421` proves build/upload, Wi-Fi join, local HTTP AI response, touch-controller readiness, server keepalive, camera capture of the `Qoder` / `OK` screen, and camera OCR on the stable `OK` marker. Supervised physical tap evidence is tracked separately from serial-trigger evidence.
