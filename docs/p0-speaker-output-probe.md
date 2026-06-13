# P0 ES8311 Speaker Output Probe

This slice validates the ES8311 output path without depending on the large vendor `canon.h` PCM sample. The board generates a short 1 kHz / 1.5 kHz tone sequence on demand, displays `SPK OK`, and the host captures audio through an avfoundation microphone to compare baseline and active energy.

## Commands

```bash
make speaker-output-build
make speaker-output-smoke
SPEAKER_VISUAL_SMOKE=1 DISPLAY_ROTATION=2 make speaker-output-smoke
```

Use `SPEAKER_AUDIO_DEVICE=<index>` to select the macOS avfoundation audio input. List devices with:

```bash
ffmpeg -hide_banner -f avfoundation -list_devices true -i ""
```

The current local default is audio device `1`, the Logitech camera microphone. This is useful when the camera is already aimed at the board, but the microphone still needs to be close enough to the board speaker for a clean energy delta.

## Acceptance Gates

- Compile: `make speaker-output-build`
- Serial: board emits `SPEAKER_OUTPUT_HEARTBEAT audio=ready`, accepts `PLAY`, and emits `SPEAKER_TONE_START` / `SPEAKER_TONE_END`
- Audio capture: host WAV active window exceeds baseline by RMS delta and ratio thresholds
- Visual: optional OCR sees `OK` on the AMOLED after playback

Default host thresholds:

```text
SPEAKER_MIN_ACTIVE_RMS=500
SPEAKER_MIN_RMS_DELTA=200
SPEAKER_MIN_RATIO=1.8
```

## Local Evidence

Last successful smoke before pausing late-night audio tests:

```text
speaker_summary baseline_rms=3183.1 active_rms=6571.7 baseline_peak=11459 active_peak=17246 rms_delta=3388.5 peak_delta=5787 ratio=2.06 wav=/Users/phodal/hardware/arduino/.logs/speaker-output-20260613-234933.wav
OCR validation passed.
```

Camera artifacts:

```text
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260613-234942.jpg
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260613-234942.processed.png
/Users/phodal/hardware/arduino/.logs/camera-ocr-20260613-234942.txt
```

## Notes

- Do not run audible speaker or microphone smoke tests late at night unless the user explicitly asks for it.
- The first implementation used Python `audioop`, but this local Python does not provide that module. The checker now parses WAV PCM with stdlib byte handling.
- The one-shot `SPEAKER_OUTPUT_READY` line can be missed if the serial checker attaches after boot. The checker also accepts `SPEAKER_OUTPUT_HEARTBEAT audio=ready`.
- The audio gate proves physical speaker output reaches the host microphone. It does not yet prove frequency accuracy, TTS quality, or closed-loop ASR/TTS behavior.
