#!/usr/bin/env python3
import argparse
import json
import os
import select
import termios
import time
import urllib.request
from pathlib import Path
from typing import Any


BAUDS = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
    230400: getattr(termios, "B230400", termios.B115200),
    460800: getattr(termios, "B460800", termios.B115200),
    921600: getattr(termios, "B921600", termios.B115200),
}


MOCK_EVENTS: dict[str, Any] = {
    "ci": {"state": "FAIL", "label": "build red"},
    "github": {"count": 7},
    "alerts": ["review needed"],
    "timer": {"minutes": 25, "start": True},
    "summary": "AI summary ready for standup",
}


class SerialPort:
    def __init__(self, path: str, baud: int) -> None:
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        self.buffer = b""
        self.configure(baud)

    def configure(self, baud: int) -> None:
        speed = BAUDS.get(baud)
        if speed is None:
            raise SystemExit(f"Unsupported baud: {baud}")
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = speed
        attrs[5] = speed
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def close(self) -> None:
        os.close(self.fd)

    def write_line(self, line: str) -> None:
        print(f"> {line}", flush=True)
        os.write(self.fd, (line.rstrip("\n") + "\n").encode("utf-8"))

    def read_lines(self, timeout: float) -> list[str]:
        deadline = time.time() + timeout
        lines: list[str] = []
        while time.time() < deadline:
            readable, _, _ = select.select([self.fd], [], [], 0.1)
            if not readable:
                continue
            chunk = os.read(self.fd, 4096)
            if not chunk:
                continue
            self.buffer += chunk
            while b"\n" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\n", 1)
                line = raw.decode("utf-8", errors="replace").strip()
                if line:
                    lines.append(line)
                    print(f"< {line}", flush=True)
        return lines

    def wait_for(self, needle: str, timeout: float) -> str:
        deadline = time.time() + timeout
        seen: list[str] = []
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                seen.append(line)
                if needle in line:
                    return line
        raise SystemExit(f"Timed out waiting for {needle!r}. Last lines: {seen[-8:]}")


def load_events(args: argparse.Namespace) -> dict[str, Any]:
    if args.mode == "mock":
        return dict(MOCK_EVENTS)
    if args.mode == "json":
        if not args.events_json:
            raise SystemExit("--events-json is required for mode=json")
        data = json.loads(Path(args.events_json).read_text(encoding="utf-8"))
    else:
        if not args.endpoint:
            raise SystemExit("--endpoint is required for mode=http")
        with urllib.request.urlopen(args.endpoint, timeout=args.timeout) as response:
            data = json.load(response)
    if not isinstance(data, dict):
        raise SystemExit("Events payload must be a JSON object")
    return data


def send_and_wait(serial: SerialPort, command: str, needle: str) -> str:
    serial.write_line(command)
    return serial.wait_for(needle, 5)


def apply_events(serial: SerialPort, events: dict[str, Any]) -> None:
    send_and_wait(serial, "PING", "PONG")

    ci = events.get("ci", {})
    if isinstance(ci, dict):
        state = str(ci.get("state", "OK")).upper()
        label = str(ci.get("label", "")).strip()
        command = f"WIDGET:CI:{state}:{label}" if label else f"WIDGET:CI:{state}"
        send_and_wait(serial, command, "WIDGET_PAGE page=STATUS")

    github = events.get("github", {})
    github_count = github.get("count", 0) if isinstance(github, dict) else github
    send_and_wait(serial, f"WIDGET:GITHUB:{int(github_count)}", "WIDGET_PAGE page=STATUS")

    alerts = events.get("alerts", [])
    if isinstance(alerts, str):
        alerts = [alerts]
    if isinstance(alerts, list):
        for alert in alerts:
            send_and_wait(serial, f"WIDGET:ALERT:{str(alert)[:48]}", "WIDGET_PAGE page=STATUS")

    timer = events.get("timer", {})
    if isinstance(timer, dict):
        minutes = int(timer.get("minutes", 25))
        send_and_wait(serial, f"TIMER:SET:{minutes}", "WIDGET_PAGE page=TIMER")
        if timer.get("start", False):
            send_and_wait(serial, "TIMER:START", "WIDGET_PAGE page=TIMER")

    summary = str(events.get("summary", "")).strip()
    if summary:
        send_and_wait(serial, f"WIDGET:SUMMARY:{summary[:80]}", "WIDGET_PAGE page=SUMMARY")

    send_and_wait(serial, "PAGE:HOME", "WIDGET_PAGE page=HOME")
    serial.write_line("STATE?")
    state = serial.wait_for("WIDGET_STATE", 5)
    if "ci=FAIL" not in state and "ci=WARN" not in state and "ci=OK" not in state:
        raise SystemExit(f"Unexpected widget state: {state}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Relay desktop events into the desk_widget serial protocol.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--mode", choices=["mock", "json", "http"], default="mock")
    parser.add_argument("--events-json")
    parser.add_argument("--endpoint")
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()

    events = load_events(args)
    serial = SerialPort(args.port, args.baud)
    try:
        serial.wait_for("WIDGET_", args.timeout)
        apply_events(serial, events)
    finally:
        serial.close()

    print(
        json.dumps(
            {
                "status": "ok",
                "mode": args.mode,
                "ci": events.get("ci", {}),
                "github": events.get("github", {}),
                "alert_count": len(events.get("alerts", [])) if isinstance(events.get("alerts", []), list) else 1,
            },
            ensure_ascii=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
