# Remaining Gates Preflight

`make remaining-gates-preflight` runs the safe side of the three incomplete goal gates:

- `official-demos`: prints the official ES7210/ES8311 physical-audio plan.
- `xiaozhi-ai`: runs the non-destructive XiaoZhi firmware/source readiness preflight.
- `audio-front-end`: rebuilds and checks the ES7210/VAD preflight artifacts without uploading, playing stimulus, or opening audio devices.

This target is intentionally not a completion shortcut. It emits `destructive=0 audio=0` and records logs under `.logs/remaining-gates-preflight/`, but the strict goal audit still requires:

- official audio physical evidence during an allowed audio window
- explicit approval before flashing XiaoZhi, followed by runtime plus visual evidence
- supervised audio-front-end physical smoke during an allowed audio window

## Commands

```bash
make remaining-gates-list
make remaining-gates-preflight
```

## Verified Locally

- `make remaining-gates-list`: listed all 3 remaining safe preflight gates with `destructive=0 audio=0`.
- `make remaining-gates-preflight`: passed all 3 safe gates with `remaining_gates_preflight_summary gates=3 passed=3 failed=0 summary=/Users/phodal/hardware/arduino/.logs/remaining-gates-preflight/20260614-105424/summary.json destructive=0 audio=0`.
- Latest summary records `official-demos` as plan-only, `xiaozhi-ai` as preflight-only with `release_source=live`, and `audio-front-end` as compile/artifact preflight with `audio_devices_used=0 stimulus_played=0 uploaded=0`.
