#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
MATRIX_PATH = ROOT / "config" / "feature-matrix.tsv"
DEFAULT_LOG_ROOT = ROOT / ".logs" / "hardware-smoke-suite"
DEFAULT_SAFE_AUDIO_MODES = {"none", "non_audio_control"}
DEFAULT_SAFE_STATUSES = {"verified", "partial"}
PHYSICAL_AUDIO_SMOKE_TARGETS = {"audio-vad-smoke", "speaker-output-smoke"}
VISUAL_ENV_KEYS = {
    "CLOUD_AI_VISUAL_SMOKE",
    "SENSOR_STATUS_VISUAL_SMOKE",
    "POWER_LIFECYCLE_VISUAL_SMOKE",
    "WIFI_CONNECTIVITY_VISUAL_SMOKE",
    "TOUCH_STATUS_VISUAL_SMOKE",
    "INTERACTION_DASHBOARD_VISUAL_SMOKE",
    "IMU_INTERACTION_VISUAL_SMOKE",
    "LVGL_VISUAL_AGENT_VISUAL_SMOKE",
    "DESK_WIDGET_VISUAL_SMOKE",
    "IOT_PANEL_VISUAL_SMOKE",
    "OFFLINE_VOICE_VISUAL_SMOKE",
    "TINYML_IMU_VISUAL_SMOKE",
    "ESP_CLAW_AGENT_VISUAL_SMOKE",
}


def load_matrix(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"{path} is empty")
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def parse_targets(args: argparse.Namespace) -> set[str]:
    targets: set[str] = set()
    for value in args.target:
        targets.update(part.strip() for part in value.split(",") if part.strip())
    if args.targets:
        targets.update(part.strip() for part in args.targets.split(",") if part.strip())
    return targets


def target_matches(row: dict[str, str], requested: set[str]) -> bool:
    return not requested or row["id"] in requested or row["smoke_target"] in requested


def smoke_uses_physical_audio(row: dict[str, str]) -> bool:
    return row["smoke_target"] in PHYSICAL_AUDIO_SMOKE_TARGETS


def skip_reason(row: dict[str, str], args: argparse.Namespace, requested: set[str]) -> str:
    if not target_matches(row, requested):
        return "not-requested"
    if row["status"] == "required_external" and not args.allow_external:
        return "external-required"
    if row["status"] == "required_quiet_window" and not args.allow_audio:
        return "quiet-window-required"
    if row["audio_mode"] == "audio" and smoke_uses_physical_audio(row) and not args.allow_audio:
        return "audio-disabled"
    if row["audio_mode"] == "conditional" and not args.allow_conditional:
        return "conditional-disabled"
    if not requested and row["audio_mode"] not in DEFAULT_SAFE_AUDIO_MODES:
        return "not-default-safe-audio-mode"
    if not requested and row["status"] not in DEFAULT_SAFE_STATUSES:
        return "not-default-safe-status"
    return ""


def selected_rows(rows: list[dict[str, str]], args: argparse.Namespace) -> list[dict[str, str]]:
    requested = parse_targets(args)
    missing = requested - {row["id"] for row in rows} - {row["smoke_target"] for row in rows}
    if missing:
        raise SystemExit(f"Unknown target(s): {', '.join(sorted(missing))}")
    return [row for row in rows if not skip_reason(row, args, requested)]


def render_list(rows: list[dict[str, str]], args: argparse.Namespace) -> None:
    requested = parse_targets(args)
    for row in rows:
        reason = skip_reason(row, args, requested)
        state = "selected" if not reason else f"skipped:{reason}"
        print(
            "suite_target "
            f"id={row['id']} smoke={row['smoke_target']} priority={row['priority']} "
            f"audio={row['audio_mode']} status={row['status']} {state}"
        )


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().strftime("%Y%m%d-%H%M%S")


def run_target(row: dict[str, str], args: argparse.Namespace, log_dir: pathlib.Path) -> dict[str, Any]:
    target = row["smoke_target"]
    target_log = log_dir / f"{row['id']}.log"
    command = ["make", target]
    env = os.environ.copy()
    env["LOG_DIR"] = str(log_dir / row["id"])
    if args.skip_build:
        env["SKIP_BUILD"] = "1"
    if args.no_visual:
        for key in VISUAL_ENV_KEYS:
            env[key] = "0"

    started = dt.datetime.now(dt.timezone.utc)
    print(f"suite_run_start id={row['id']} target={target} log={target_log}", flush=True)
    target_log.parent.mkdir(parents=True, exist_ok=True)
    timed_out = False
    with target_log.open("w", encoding="utf-8") as handle:
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
                timeout=args.per_target_timeout,
            )
            output = completed.stdout or ""
            returncode = completed.returncode
        except subprocess.TimeoutExpired as exc:
            output = "Timed out after %.1f seconds\n" % args.per_target_timeout
            if isinstance(exc.output, str):
                output = exc.output + output
            returncode = 124
            timed_out = True
        handle.write(output)
        handle.flush()
        print(output, end="")

    finished = dt.datetime.now(dt.timezone.utc)
    elapsed = (finished - started).total_seconds()
    status = "timeout" if timed_out else ("passed" if returncode == 0 else "failed")
    result: dict[str, Any] = {
        "id": row["id"],
        "target": target,
        "status": status,
        "returncode": returncode,
        "seconds": round(elapsed, 3),
        "log": str(target_log),
    }
    print(
        "suite_run_done "
        f"id={row['id']} status={status} returncode={returncode} seconds={elapsed:.1f} log={target_log}",
        flush=True,
    )
    return result


def run_camera_ready(args: argparse.Namespace, log_dir: pathlib.Path) -> dict[str, Any]:
    target_log = log_dir / "camera-ready.log"
    command = ["make", "camera-ready"]
    env = os.environ.copy()
    env["LOG_DIR"] = str(log_dir / "camera-ready")

    started = dt.datetime.now(dt.timezone.utc)
    print(f"suite_preflight_start id=camera-ready target=camera-ready log={target_log}", flush=True)
    target_log.parent.mkdir(parents=True, exist_ok=True)
    timed_out = False
    with target_log.open("w", encoding="utf-8") as handle:
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
                timeout=args.camera_ready_timeout,
            )
            output = completed.stdout or ""
            returncode = completed.returncode
        except subprocess.TimeoutExpired as exc:
            output = "Timed out after %.1f seconds\n" % args.camera_ready_timeout
            if isinstance(exc.output, str):
                output = exc.output + output
            returncode = 124
            timed_out = True
        handle.write(output)
        handle.flush()
        print(output, end="")

    finished = dt.datetime.now(dt.timezone.utc)
    elapsed = (finished - started).total_seconds()
    status = "timeout" if timed_out else ("passed" if returncode == 0 else "failed")
    result: dict[str, Any] = {
        "id": "camera-ready",
        "target": "camera-ready",
        "kind": "preflight",
        "status": status,
        "returncode": returncode,
        "seconds": round(elapsed, 3),
        "log": str(target_log),
    }
    print(
        "suite_preflight_done "
        f"id=camera-ready status={status} returncode={returncode} seconds={elapsed:.1f} log={target_log}",
        flush=True,
    )
    return result


def write_summary(results: list[dict[str, Any]], log_dir: pathlib.Path) -> None:
    summary_path = log_dir / "summary.json"
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "results": results,
        "passed": sum(1 for item in results if item["status"] == "passed"),
        "failed": sum(1 for item in results if item["status"] != "passed"),
    }
    summary_path.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"suite_summary path={summary_path} passed={payload['passed']} failed={payload['failed']}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run serialized hardware smoke targets from the feature matrix.")
    parser.add_argument("--matrix", default=str(MATRIX_PATH))
    parser.add_argument("--list", action="store_true", help="List selected/skipped targets without running them.")
    parser.add_argument("--dry-run", action="store_true", help="Print the selected commands without running them.")
    parser.add_argument("--target", action="append", default=[], help="Feature id or Makefile smoke target to run.")
    parser.add_argument("--targets", help="Comma-separated feature ids or Makefile smoke targets to run.")
    parser.add_argument("--allow-audio", action="store_true", help="Allow audio lanes. Do not use late at night.")
    parser.add_argument("--allow-conditional", action="store_true", help="Allow conditional lanes such as official demos.")
    parser.add_argument("--allow-external", action="store_true", help="Allow externally gated lanes such as XiaoZhi.")
    parser.add_argument("--skip-build", action="store_true", help="Pass SKIP_BUILD=1 to upload scripts.")
    parser.add_argument(
        "--with-visual",
        action="store_false",
        dest="no_visual",
        default=True,
        help="Allow per-target visual OCR env vars from the current environment.",
    )
    parser.add_argument(
        "--skip-camera-ready",
        action="store_true",
        help="Skip the camera-ready preflight even when --with-visual is set.",
    )
    parser.add_argument("--camera-ready-timeout", type=float, default=30.0)
    parser.add_argument("--log-dir", default=str(DEFAULT_LOG_ROOT / timestamp()))
    parser.add_argument("--max-failures", type=int, default=1)
    parser.add_argument("--per-target-timeout", type=float, default=900.0)
    args = parser.parse_args()

    rows = load_matrix(pathlib.Path(args.matrix))
    if args.list:
        render_list(rows, args)
        return 0

    selected = selected_rows(rows, args)
    if not selected:
        raise SystemExit("No hardware smoke targets selected.")

    if args.dry_run:
        if not args.no_visual and not args.skip_camera_ready:
            print("dry_run id=camera-ready command=make camera-ready")
        for row in selected:
            print(f"dry_run id={row['id']} command=make {row['smoke_target']}")
        return 0

    log_dir = pathlib.Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    if not args.no_visual and not args.skip_camera_ready:
        preflight = run_camera_ready(args, log_dir)
        results.append(preflight)
        if preflight["status"] != "passed":
            print("suite_abort reason=camera-ready-failed", flush=True)
            write_summary(results, log_dir)
            return 1

    failures = 0
    for row in selected:
        result = run_target(row, args, log_dir)
        results.append(result)
        if result["status"] != "passed":
            failures += 1
            if failures >= args.max_failures:
                print(f"suite_abort failures={failures} max_failures={args.max_failures}", flush=True)
                break
    write_summary(results, log_dir)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
