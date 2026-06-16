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
        "command": ["make", "xiaozhi-readiness"],
        "safe_scope": "preflight-source-build-existing-backup",
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
    {
        "id": "web-ai-button",
        "reason": "external-required",
        "command": ["make", "web-ai-button-tap-smoke"],
        "safe_scope": "supervised-physical-tap",
        "destructive": "0",
        "audio": "0",
        "manual_required": "1",
        "physical_followup": "make web-ai-button-tap-smoke",
    },
]


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().strftime("%Y%m%d-%H%M%S")


def rel(path: str | pathlib.Path) -> str:
    try:
        return str(pathlib.Path(path).resolve().relative_to(ROOT))
    except (OSError, ValueError):
        return str(path)


def latest_summary(log_root: pathlib.Path) -> pathlib.Path | None:
    summaries = sorted(log_root.glob("*/summary.json"))
    return summaries[-1] if summaries else None


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
        "manual_required": gate.get("manual_required", "0"),
    }


def skip_manual_gate(gate: dict[str, str], log_dir: pathlib.Path) -> dict[str, Any]:
    log_path = log_dir / f"{gate['id']}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    message = (
        "Skipped by default because this gate requires supervised physical input. "
        f"Run `{' '.join(gate['command'])}` when a human can tap the board."
    )
    log_path.write_text(message + "\n", encoding="utf-8")
    print(
        "remaining_gate_skipped "
        f"id={gate['id']} status=skipped reason=manual-required log={log_path} "
        f"destructive={gate['destructive']} audio={gate['audio']}",
        flush=True,
    )
    return {
        "id": gate["id"],
        "reason": gate["reason"],
        "command": gate["command"],
        "safe_scope": gate["safe_scope"],
        "status": "skipped",
        "skip_reason": "manual-required",
        "returncode": None,
        "seconds": 0.0,
        "log": str(log_path),
        "destructive": gate["destructive"],
        "audio": gate["audio"],
        "physical_followup": gate["physical_followup"],
        "manual_required": gate.get("manual_required", "0"),
    }


def write_summary(results: list[dict[str, Any]], log_dir: pathlib.Path) -> pathlib.Path:
    summary_path = log_dir / "summary.json"
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "purpose": "Safe preflight for goal-completion items that still require an audio window, explicit flash approval, or supervised manual input.",
        "results": results,
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "skipped": sum(1 for item in results if item["status"] == "skipped"),
        "failed": sum(1 for item in results if item["status"] not in {"passed", "skipped"}),
        "destructive": "0",
        "audio": "0",
    }
    summary_path.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    return summary_path


def render_markdown(payload: dict[str, Any], summary_path: pathlib.Path) -> str:
    results = payload.get("results", [])
    lines = [
        "# Remaining Gates Preflight",
        "",
        "Generated by `scripts/remaining-gates-preflight.py --markdown`.",
        "",
        "`make remaining-gates-preflight` tracks the safe side of the four incomplete goal gates. It is intentionally not a completion shortcut: it records no-audio, non-destructive preflight evidence while preserving the strict requirement for later physical audio, explicit XiaoZhi flash approval, or supervised tap evidence.",
        "",
        f"Latest summary: `{rel(summary_path)}`",
        f"Generated at: `{payload.get('generated_at', 'unknown')}`",
        f"Summary: `passed={payload.get('passed', 0)}` `skipped={payload.get('skipped', 0)}` `failed={payload.get('failed', 0)}` `destructive={payload.get('destructive', '?')}` `audio={payload.get('audio', '?')}`",
        "",
        "| ID | Safe scope | Status | Log | Follow-up required |",
        "| --- | --- | --- | --- | --- |",
    ]
    for item in results:
        log = rel(item.get("log", ""))
        status = item.get("status", "unknown")
        if item.get("skip_reason"):
            status = f"{status} ({item['skip_reason']})"
        lines.append(
            "| {id} | {safe_scope} | {status} | `{log}` | {followup} |".format(
                id=item.get("id", ""),
                safe_scope=item.get("safe_scope", ""),
                status=status,
                log=log,
                followup=item.get("physical_followup", ""),
            )
        )
    lines.extend(
        [
            "",
            "## Completion Boundary",
            "",
            "This evidence still does not complete the remaining gates. Strict completion still requires:",
            "",
            "- official ES7210/ES8311 physical audio evidence during an allowed audio window",
            "- explicit approval before flashing XiaoZhi, followed by runtime plus visual evidence",
            "- supervised Web AI Button physical tap evidence on the AMOLED",
            "- supervised audio-front-end physical smoke during an allowed audio window",
            "",
            "## Commands",
            "",
            "```bash",
            "make remaining-gates-list",
            "make remaining-gates-preflight",
            "make remaining-gates-doc",
            "make remaining-gates-preflight REMAINING_GATES_ARGS=--include-manual",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run safe preflights for the remaining incomplete hardware gates.")
    parser.add_argument("--log-dir", default=str(DEFAULT_LOG_ROOT / timestamp()))
    parser.add_argument("--timeout", type=float, default=240.0)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--markdown", action="store_true", help="Render markdown from the latest or selected preflight summary.")
    parser.add_argument("--summary", help="Summary JSON to render with --markdown. Defaults to the latest summary under .logs/remaining-gates-preflight/.")
    parser.add_argument(
        "--include-manual",
        action="store_true",
        help="Also run gates that require supervised physical input, such as tapping the AMOLED.",
    )
    args = parser.parse_args()

    if args.markdown:
        summary_path = pathlib.Path(args.summary) if args.summary else latest_summary(DEFAULT_LOG_ROOT)
        if summary_path is None:
            raise SystemExit("No remaining-gates preflight summary found. Run `make remaining-gates-preflight` first.")
        payload = json.loads(summary_path.read_text(encoding="utf-8"))
        print(render_markdown(payload, summary_path), end="")
        return 0

    if args.list:
        for gate in GATES:
            print(
                "remaining_gate "
                f"id={gate['id']} reason={gate['reason']} command={' '.join(gate['command'])!r} "
                f"safe_scope={gate['safe_scope']} destructive={gate['destructive']} audio={gate['audio']} "
                f"manual_required={gate.get('manual_required', '0')} "
                f"physical_followup={gate['physical_followup']!r}"
            )
        print(f"remaining_gates_preflight_summary gates={len(GATES)} mode=list destructive=0 audio=0")
        return 0

    log_dir = pathlib.Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    results = [
        run_gate(gate, log_dir, args.timeout)
        if args.include_manual or gate.get("manual_required", "0") != "1"
        else skip_manual_gate(gate, log_dir)
        for gate in GATES
    ]
    summary_path = write_summary(results, log_dir)
    failed = sum(1 for item in results if item["status"] not in {"passed", "skipped"})
    skipped = sum(1 for item in results if item["status"] == "skipped")
    print(
        "remaining_gates_preflight_summary "
        f"gates={len(results)} passed={sum(1 for item in results if item['status'] == 'passed')} "
        f"skipped={skipped} failed={failed} "
        f"summary={summary_path} destructive=0 audio=0"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
