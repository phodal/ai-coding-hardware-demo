#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_LOG_ROOT = ROOT / ".logs" / "remaining-gates-preflight"


GATES = [
    {
        "id": "official-demos",
        "reason": "conditional-physical-evidence-required",
        "command": ["make", "official-audio-physical-plan"],
        "safe_scope": "plan-only",
        "destructive": "0",
        "audio": "0",
        "physical_followup": "ALLOW_AUDIO=1 OFFICIAL_AUDIO_OUTPUT_CONFIRM=heard make official-audio-physical-smoke",
    },
    {
        "id": "xiaozhi-ai",
        "reason": "external-required",
        "command": ["make", "xiaozhi-preflight"],
        "safe_scope": "preflight-only",
        "destructive": "0",
        "audio": "0",
        "physical_followup": "CONFIRM=--yes make xiaozhi-flash && make xiaozhi-runtime-visual-check",
    },
    {
        "id": "audio-front-end",
        "reason": "quiet-window-required",
        "command": ["make", "audio-vad-preflight"],
        "safe_scope": "compile-and-artifact-preflight",
        "destructive": "0",
        "audio": "0",
        "physical_followup": 'make hardware-smoke-suite HARDWARE_SMOKE_ARGS="--target audio-front-end --allow-audio"',
    },
]


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().strftime("%Y%m%d-%H%M%S")


def run_gate(gate: dict[str, str], log_dir: pathlib.Path, timeout: float) -> dict[str, Any]:
    log_path = log_dir / f"{gate['id']}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["LOG_DIR"] = str(log_dir / gate["id"])
    started = dt.datetime.now(dt.timezone.utc)
    command = list(gate["command"])
    print(
        "remaining_gate_start "
        f"id={gate['id']} command={' '.join(command)!r} log={log_path} "
        f"destructive={gate['destructive']} audio={gate['audio']}",
        flush=True,
    )

    timed_out = False
    with log_path.open("w", encoding="utf-8") as handle:
        handle.write(f"$ {' '.join(command)}\n")
        handle.flush()
        try:
            completed = subprocess.run(
                command,
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=timeout,
            )
            output = completed.stdout or ""
            returncode = completed.returncode
        except subprocess.TimeoutExpired as exc:
            output = ""
            if isinstance(exc.output, str):
                output += exc.output
            output += f"Timed out after {timeout:.1f} seconds\n"
            returncode = 124
            timed_out = True
        handle.write(output)
        handle.flush()
        print(output, end="")

    finished = dt.datetime.now(dt.timezone.utc)
    seconds = (finished - started).total_seconds()
    status = "timeout" if timed_out else ("passed" if returncode == 0 else "failed")
    print(
        "remaining_gate_done "
        f"id={gate['id']} status={status} returncode={returncode} seconds={seconds:.1f} "
        f"log={log_path} destructive={gate['destructive']} audio={gate['audio']}",
        flush=True,
    )
    return {
        "id": gate["id"],
        "reason": gate["reason"],
        "command": command,
        "safe_scope": gate["safe_scope"],
        "status": status,
        "returncode": returncode,
        "seconds": round(seconds, 3),
        "log": str(log_path),
        "destructive": gate["destructive"],
        "audio": gate["audio"],
        "physical_followup": gate["physical_followup"],
    }


def write_summary(results: list[dict[str, Any]], log_dir: pathlib.Path) -> pathlib.Path:
    summary_path = log_dir / "summary.json"
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "purpose": "Safe preflight for goal-completion items that still require audio-window or explicit flash approval.",
        "results": results,
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "failed": sum(1 for item in results if item["status"] != "passed"),
        "destructive": "0",
        "audio": "0",
    }
    summary_path.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return summary_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run safe preflights for the remaining incomplete hardware gates.")
    parser.add_argument("--log-dir", default=str(DEFAULT_LOG_ROOT / timestamp()))
    parser.add_argument("--timeout", type=float, default=240.0)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.list:
        for gate in GATES:
            print(
                "remaining_gate "
                f"id={gate['id']} reason={gate['reason']} command={' '.join(gate['command'])!r} "
                f"safe_scope={gate['safe_scope']} destructive={gate['destructive']} audio={gate['audio']} "
                f"physical_followup={gate['physical_followup']!r}"
            )
        print(f"remaining_gates_preflight_summary gates={len(GATES)} mode=list destructive=0 audio=0")
        return 0

    log_dir = pathlib.Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    results = [run_gate(gate, log_dir, args.timeout) for gate in GATES]
    summary_path = write_summary(results, log_dir)
    failed = sum(1 for item in results if item["status"] != "passed")
    print(
        "remaining_gates_preflight_summary "
        f"gates={len(results)} passed={len(results) - failed} failed={failed} "
        f"summary={summary_path} destructive=0 audio=0"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
