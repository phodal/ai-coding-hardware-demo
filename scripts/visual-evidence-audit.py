#!/usr/bin/env python3
import argparse
import csv
import json
import pathlib
import re
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
MATRIX_PATH = ROOT / "config" / "feature-matrix.tsv"
SMOKE_SUITE_LOG_ROOT = ROOT / ".logs" / "hardware-smoke-suite"
CAMERA_PATH_RE = re.compile(r"(?:/Users/[^`\\s)]*/hardware/arduino/)?\.logs/camera-ocr-[0-9-]+\.(?:jpg|jpeg|png|txt)")
VISUAL_TERMS = (
    "VISUAL_SMOKE",
    "camera OCR",
    "Camera OCR",
    "camera-ocr",
    "OCR validation passed",
    "visual artifact",
    "visual proof",
    "visual-smoke",
)


def load_matrix(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"{path} is empty")
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def read_text(path: pathlib.Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def verified_section(text: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    in_section = False
    for line in lines:
        if line.strip() == "## Verified Locally":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            out.append(line)
    return "\n".join(out)


def rel(path: str | pathlib.Path) -> str:
    try:
        return str(pathlib.Path(path).resolve().relative_to(ROOT))
    except (OSError, ValueError):
        return str(path)


def normalize_artifact(path_text: str) -> pathlib.Path:
    path = pathlib.Path(path_text)
    if path.is_absolute():
        return path
    return ROOT / path


def artifact_paths(text: str) -> list[str]:
    paths: list[str] = []
    seen: set[str] = set()
    for match in CAMERA_PATH_RE.finditer(text):
        item = match.group(0)
        if item not in seen:
            paths.append(item)
            seen.add(item)
    return paths


def latest_camera_ready_preflight() -> dict[str, Any] | None:
    candidates: list[tuple[float, pathlib.Path, dict[str, Any]]] = []
    for summary_path in SMOKE_SUITE_LOG_ROOT.glob("*/summary.json"):
        try:
            payload = json.loads(summary_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for result in payload.get("results", []):
            if result.get("id") != "camera-ready":
                continue
            try:
                mtime = summary_path.stat().st_mtime
            except OSError:
                mtime = 0.0
            candidates.append((mtime, summary_path, result))
            break
    if not candidates:
        return None

    _, summary_path, result = max(candidates, key=lambda item: item[0])
    return {
        "summary": rel(summary_path),
        "log": rel(result.get("log", "")),
        "status": result.get("status", "unknown"),
        "returncode": result.get("returncode", "unknown"),
        "seconds": result.get("seconds", "unknown"),
    }


def visual_status(row: dict[str, str], doc_text: str, verified_text: str) -> tuple[str, str]:
    verified_artifacts = artifact_paths(verified_text)
    if verified_artifacts:
        missing = [item for item in verified_artifacts if not normalize_artifact(item).exists()]
        if missing:
            return "artifact-missing", f"Referenced camera artifact is missing: {', '.join(missing[:2])}"
        return "camera-verified", "Verified Locally references camera OCR artifact(s)."

    for line in verified_text.splitlines():
        line_lower = line.lower()
        if ("camera ocr" in line_lower or "ocr validation" in line_lower) and ("passed" in line_lower or "artifact" in line_lower):
            return "camera-verified-no-artifact", "Verified Locally says camera OCR passed, but does not reference a saved artifact."

    verified_lower = verified_text.lower()
    if "ocr validation passed" in verified_lower:
        return "camera-verified-no-artifact", "Verified Locally says camera OCR passed, but does not reference a saved artifact."

    if any(term in doc_text for term in VISUAL_TERMS):
        if row["status"] == "required_external":
            return "post-flash-required", "Visual gate is documented, but needs approved external firmware/runtime evidence."
        if row["status"] == "required_quiet_window" or row["audio_mode"] == "audio":
            return "audio-window-required", "Visual gate exists, but physical audio evidence remains gated."
        return "visual-gate-documented", "Visual smoke path is documented but no local camera artifact is recorded."

    return "missing-visual-gate", "Add a camera OCR or equivalent visual validation path."


def audit_rows(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for row in rows:
        doc_path = ROOT / row["doc"]
        doc_text = read_text(doc_path)
        verified_text = verified_section(doc_text)
        status, gap = visual_status(row, doc_text, verified_text)
        artifacts = artifact_paths(verified_text)
        records.append(
            {
                **row,
                "visual_status": status,
                "visual_gap": gap,
                "artifact_count": len(artifacts),
                "artifacts": [rel(normalize_artifact(item)) for item in artifacts[:3]],
            }
        )
    return records


def render_markdown(records: list[dict[str, Any]]) -> str:
    camera_verified = sum(1 for item in records if item["visual_status"].startswith("camera-verified"))
    camera_preflight = latest_camera_ready_preflight()
    lines = [
        "# Visual Evidence Audit",
        "",
        "Generated by `scripts/visual-evidence-audit.py --markdown`.",
        "",
        "This report audits camera/OCR evidence for feature directions. It is a visual-evidence layer, not a replacement for serial, build, suite, audio, or external-firmware gates.",
        "",
        f"Summary: `{camera_verified}` of `{len(records)}` feature directions currently reference camera/OCR evidence in their local evidence section.",
        "",
        "| ID | Priority | Matrix status | Audio mode | Visual status | Artifacts | Next visual gap |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    if camera_preflight:
        lines[7:7] = [
            "Latest camera-ready preflight:",
            "",
            f"- Status: `{camera_preflight['status']}`",
            f"- Summary: `{camera_preflight['summary']}`",
            f"- Log: `{camera_preflight['log']}`",
            f"- Return code: `{camera_preflight['returncode']}`",
            "",
        ]
    details: list[str] = []
    for item in records:
        artifact_text = ", ".join(f"`{path}`" for path in item["artifacts"]) if item["artifacts"] else "none"
        lines.append(
            "| {id} | {priority} | {status} | {audio_mode} | {visual_status} | {artifacts} | {gap} |".format(
                id=item["id"],
                priority=item["priority"],
                status=item["status"],
                audio_mode=item["audio_mode"],
                visual_status=item["visual_status"],
                artifacts=artifact_text,
                gap=item["visual_gap"],
            )
        )
        details.extend(["", f"## {item['id']}", "", f"- Doc: `{item['doc']}`", f"- Visual status: `{item['visual_status']}`"])
        if item["artifacts"]:
            details.append("- Camera artifacts:")
            details.extend(f"  - `{path}`" for path in item["artifacts"])
        else:
            details.append("- Camera artifacts: none recorded in `## Verified Locally`.")
        details.append(f"- Next visual gap: {item['visual_gap']}")
    lines.extend(details)
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit camera/OCR evidence across hardware feature docs.")
    parser.add_argument("--matrix", default=str(MATRIX_PATH))
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()

    records = audit_rows(load_matrix(pathlib.Path(args.matrix)))
    camera_preflight = latest_camera_ready_preflight()
    if args.markdown:
        print(render_markdown(records), end="")
        return 0

    if camera_preflight:
        print(
            "visual_evidence_camera_preflight "
            f"status={camera_preflight['status']} returncode={camera_preflight['returncode']} "
            f"summary={camera_preflight['summary']} log={camera_preflight['log']}"
        )

    camera_verified = 0
    for item in records:
        if item["visual_status"].startswith("camera-verified"):
            camera_verified += 1
        print(
            "visual_evidence "
            f"id={item['id']} status={item['visual_status']} artifacts={item['artifact_count']} "
            f"gap={item['visual_gap']}"
        )
    print(f"visual_evidence_summary features={len(records)} camera_verified={camera_verified}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
