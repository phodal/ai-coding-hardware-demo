# P0 Audio VAD Probe

This lane verifies the microphone side of the self-developed cloud AI terminal before full ASR streaming is implemented.

The probe uses the board's ES7210 microphone input and ESP-SR VAD, then reports simple serial metrics:

- `AUDIO_VAD_READY`
- `AUDIO_METRIC rms=<value> peak=<value> speech=<0|1>`
- `AUDIO_SPEECH_DETECTED ...` when VAD fires

## Commands

```bash
make audio-vad-build
make audio-vad-smoke
AUDIO_VAD_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make audio-vad-smoke
```

The host smoke script uploads `sketches/audio_vad_probe`, waits for `AUDIO_VAD_READY`, plays a macOS `say` stimulus by default, and validates that captured RMS/peak metrics rise above thresholds.

Useful overrides:

```bash
AUDIO_VAD_STIMULUS_COMMAND="say 'testing microphone input'"
AUDIO_VAD_MIN_RMS=5
AUDIO_VAD_MIN_PEAK=20
AUDIO_VAD_MIN_RMS_DELTA=5
AUDIO_VAD_MIN_PEAK_DELTA=10
AUDIO_VAD_REQUIRE_SPEECH=1
```

## Verification Notes

- RMS/peak thresholds validate microphone data flow even when VAD is conservative.
- `AUDIO_VAD_REQUIRE_SPEECH=1` is stricter and should be used when the host speaker is physically close enough to the board microphone.
- Camera OCR can verify the display reaches `OK` after the probe detects a signal.

## Verified Locally

- `make audio-vad-build`: passed.
- `AUDIO_VAD_ACTIVE_SECONDS=8 AUDIO_VAD_BASELINE_SECONDS=2 make audio-vad-smoke`: uploaded to `/dev/cu.usbmodem83101` and passed.
- Observed summary: `baseline_max_rms=0`, `baseline_max_peak=3`, `active_max_rms=14`, `active_max_peak=40`, `rms_delta=14`, `peak_delta=37`.
- VAD did not fire with the current host-speaker placement, so `AUDIO_VAD_REQUIRE_SPEECH=1` remains a stricter manual/fixture-dependent gate.
- `CAMERA_DEVICE=0 CAMERA_SIZE=1280x720 OCR_ENGINE=vision OCR_EXPECTED=OK ./scripts/camera-ocr.sh`: passed after the audio smoke, latest artifact `.logs/camera-ocr-20260613-231624.jpg`.
