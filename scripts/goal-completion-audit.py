#!/usr/bin/env python3
import argparse
import csv
import json
import pathlib
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
MATRIX_PATH = ROOT / "config" / "feature-matrix.tsv"
SUITE_ROOT = ROOT / ".logs" / "hardware-smoke-suite"


def load_matrix(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"{path} is empty")
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def verified_bullets(doc_path: pathlib.Path) -> list[str]:
    if not doc_path.exists():
        return []
    lines = doc_path.read_text(encoding="utf-8").splitlines()
    in_section = False
    bullets: list[str] = []
    for line in lines:
        if line.strip() == "## Verified Locally":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section and line.startswith("- "):
            bullets.append(line[2:].strip())
    return bullets


def load_suite_results(root: pathlib.Path) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    if not root.exists():
        return latest
    for summary_path in sorted(root.glob("*/summary.json")):
        try:
            payload = json.loads(summary_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        generated_at = str(payload.get("generated_at", ""))
        for item in payload.get("results", []):
            if not isinstance(item, dict) or "id" not in item:
                continue
            row_id = str(item["id"])
            record = dict(item)
            record["summary"] = str(summary_path)
            record["generated_at"] = generated_at
            if row_id not in latest or generated_at >= str(latest[row_id].get("generated_at", "")):
                latest[row_id] = record
    return latest


def rel(path: str | pathlib.Path) -> str:
    try:
        return str(pathlib.Path(path).resolve().relative_to(ROOT))
    except (OSError, ValueError):
        return str(path)


def completion_state(row: dict[str, str], bullets: list[str], suite: dict[str, Any] | None) -> str:
    if not bullets:
        return "missing-doc-evidence"
    if row["status"] == "required_quiet_window":
        return "quiet-window-required"
    if row["status"] == "required_external":
        return "external-required"
    if row["status"] == "partial":
        return "partial-implementation"
    if row["audio_mode"] == "conditional":
        return "conditional-physical-evidence-required"
    if row["audio_mode"] == "audio":
        return "audio-physical-evidence-required"
    if not suite:
        return "missing-suite-evidence"
    if suite.get("status") != "passed":
        return "latest-suite-not-passed"
    return "complete"


def next_action(row: dict[str, str], state: str) -> str:
    if state == "complete":
        return "No immediate action."
    if state == "missing-doc-evidence":
        return "Add exact Verified Locally evidence to the feature doc."
    if state == "quiet-window-required":
        return "Safe now: run `make audio-afe-readiness` and `make audio-vad-preflight`; during an allowed audio window run `make hardware-smoke-suite HARDWARE_SMOKE_ARGS=\"--target audio-front-end --allow-audio\"` and record the result."
    if state == "external-required":
        return "Keep `make xiaozhi-preflight` and `make xiaozhi-backup` current; after explicit flash approval run `CONFIRM=--yes make xiaozhi-flash`, then `make xiaozhi-runtime-visual-check` before any audio interaction."
    if state == "partial-implementation":
        return "Finish the remaining feature behavior, then promote matrix status only after broad hardware evidence."
    if state == "conditional-physical-evidence-required":
        return "Run `make official-audio-physical-plan`; during an allowed audio window run `ALLOW_AUDIO=1 make official-audio-physical-smoke`, adding `OFFICIAL_AUDIO_OUTPUT_CONFIRM=heard` for supervised ES8311 output evidence."
    if state == "audio-physical-evidence-required":
        return "Collect supervised audio hardware evidence."
    if state == "missing-suite-evidence":
        return "Run the feature through hardware-smoke-suite when safe."
    if state == "latest-suite-not-passed":
        return "Investigate the latest suite failure and rerun."
    return "Review evidence manually."


def audit_rows(rows: list[dict[str, str]], suite_results: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for row in rows:
        bullets = verified_bullets(ROOT / row["doc"])
        suite = suite_results.get(row["id"])
        state = completion_state(row, bullets, suite)
        records.append(
            {
                **row,
                "doc_items": len(bullets),
                "suite_status": suite.get("status", "missing") if suite else "missing",
                "suite_summary": rel(str(suite.get("summary", ""))) if suite else "",
                "completion": state,
                "complete": state == "complete",
                "next_action": next_action(row, state),
            }
        )
    return records


def render_markdown(records: list[dict[str, Any]]) -> str:
    complete = sum(1 for item in records if item["complete"])
    lines = [
        "# Goal Completion Audit",
        "",
        "Generated by `scripts/goal-completion-audit.py --markdown`.",
        "",
        "This report is stricter than the evidence audit. A feature is complete only when the implementation is not partial, is not externally gated, is not waiting on a quiet-window or conditional physical check, and has passing suite evidence where applicable.",
        "",
        f"Summary: `{complete}` of `{len(records)}` feature directions are currently complete under this stricter gate.",
        "",
        "| ID | Priority | Matrix status | Audio mode | Suite | Completion | Next action |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in records:
        suite_text = item["suite_status"]
        if item["suite_summary"]:
            suite_text = f"{suite_text} `{item['suite_summary']}`"
        lines.append(
            "| {id} | {priority} | {status} | {audio_mode} | {suite} | {completion} | {next_action} |".format(
                id=item["id"],
                priority=item["priority"],
                status=item["status"],
                audio_mode=item["audio_mode"],
                suite=suite_text,
                completion=item["completion"],
                next_action=item["next_action"],
            )
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit the full board goal at requirement level.")
    parser.add_argument("--matrix", default=str(MATRIX_PATH))
    parser.add_argument("--suite-root", default=str(SUITE_ROOT))
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--strict", action="store_true", help="Return non-zero when any feature is incomplete.")
    args = parser.parse_args()

    records = audit_rows(load_matrix(pathlib.Path(args.matrix)), load_suite_results(pathlib.Path(args.suite_root)))
    if args.markdown:
        print(render_markdown(records), end="")
        return 0

    complete = sum(1 for item in records if item["complete"])
    incomplete = len(records) - complete
    print(f"goal_completion_summary features={len(records)} complete={complete} incomplete={incomplete}")
    for item in records:
        print(
            "goal_completion "
            f"id={item['id']} status={item['status']} audio={item['audio_mode']} "
            f"suite={item['suite_status']} completion={item['completion']}"
        )
    return 1 if args.strict and incomplete else 0


if __name__ == "__main__":
    sys.exit(main())
