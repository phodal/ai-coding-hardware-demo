#!/usr/bin/env python3
import argparse
import os
import re
import select
import termios
import time


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

READY_RE = re.compile(r"TOUCH_READY model=(?P<model>\S+) points=(?P<points>\d+)")
STATUS_RE = re.compile(r"TOUCH_STATUS .*ready=(?P<ready>[01]) model=(?P<model>\S+) events=(?P<events>\d+)")
EVENT_RE = re.compile(r"TOUCH_EVENT .*points=(?P<points>\d+) x=(?P<x>-?\d+) y=(?P<y>-?\d+)")


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

    def wait_for_any(self, needles: list[str], timeout: float) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                if any(needle in line for needle in needles):
                    return line
        raise SystemExit(f"Timed out waiting for any of {needles!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate CST92xx touch controller serial status.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=8.0)
    parser.add_argument("--require-event", action="store_true")
    parser.add_argument("--min-points", type=int, default=1)
    args = parser.parse_args()

    ready_line = ""
    serial = SerialPort(args.port, args.baud)
    try:
        ready_line = serial.wait_for_any(["TOUCH_READY", "TOUCH_STATUS", "TOUCH_FAILED"], 15)
        lines = [ready_line] + serial.read_lines(args.seconds)
    finally:
        serial.close()

    ready = None
    statuses = []
    events = []
    for line in lines:
        match = READY_RE.search(line)
        if match:
            ready = match.groupdict()
            continue
        match = STATUS_RE.search(line)
        if match:
            statuses.append(match.groupdict())
            continue
        match = EVENT_RE.search(line)
        if match:
            events.append({key: int(value) for key, value in match.groupdict().items()})

    if ready is None and not any(item["ready"] == "1" for item in statuses):
        raise SystemExit("Touch controller never reported ready.")

    points = int(ready["points"]) if ready else args.min_points
    if points < args.min_points:
        raise SystemExit(f"support points {points} < required {args.min_points}")

    if args.require_event and not events:
        raise SystemExit("No TOUCH_EVENT captured; touch the screen during the smoke window.")

    model = ready["model"] if ready else statuses[-1]["model"]
    max_events = max([item["events"] for item in statuses], default="0")
    print(
        "touch_summary "
        f"model={model} support_points={points} status_lines={len(statuses)} "
        f"events={len(events)} reported_events={max_events}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
