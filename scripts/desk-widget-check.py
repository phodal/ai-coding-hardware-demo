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

READY_RE = re.compile(r"WIDGET_(?:READY|PARTIAL) display=(?P<display>[01]) touch=(?P<touch>[01])")
PAGE_RE = re.compile(r"WIDGET_PAGE page=(?P<page>\S+) source=(?P<source>\S+)")
STATE_RE = re.compile(
    r"WIDGET_STATE .*page=(?P<page>\S+) display=(?P<display>[01]) touch=(?P<touch>[01]) "
    r"ci=(?P<ci>\S+) github=(?P<github>\d+) alerts=(?P<alerts>\d+) "
    r"timer=(?P<timer>\d+) running=(?P<running>[01]) summary_len=(?P<summary_len>\d+)"
)
ALERT_RE = re.compile(r"WIDGET_ALERT count=(?P<count>\d+) text=(?P<text>.*)")


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

    def write_line(self, text: str) -> None:
        print(f"> {text}", flush=True)
        os.write(self.fd, (text + "\n").encode("utf-8"))

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

    def wait_for(self, predicate, timeout: float, label: str) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                if predicate(line):
                    return line
        raise SystemExit(f"Timed out waiting for {label}")


def parse_states(lines: list[str]) -> list[dict[str, str | int]]:
    states = []
    for line in lines:
        match = STATE_RE.search(line)
        if not match:
            continue
        item: dict[str, str | int] = {}
        for key, value in match.groupdict().items():
            if key in {"page", "ci"}:
                item[key] = value
            else:
                item[key] = int(value)
        states.append(item)
    return states


def parse_pages(lines: list[str]) -> list[str]:
    pages = []
    for line in lines:
        match = PAGE_RE.search(line)
        if match and match.group("source") == "serial":
            pages.append(match.group("page"))
    return pages


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the serial-driven desk widget.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--allow-touch-missing", action="store_true")
    args = parser.parse_args()

    collected: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        ready_line = serial.wait_for(
            lambda line: line.startswith("WIDGET_READY")
            or line.startswith("WIDGET_PARTIAL")
            or line.startswith("WIDGET_STATE"),
            15,
            "WIDGET_READY",
        )
        collected.append(ready_line)
        ready = READY_RE.search(ready_line)
        state_ready = STATE_RE.search(ready_line)
        if ready:
            if ready.group("display") != "1":
                raise SystemExit("Widget display did not report ready.")
            if ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("Widget touch did not report ready.")
        elif state_ready:
            if state_ready.group("display") != "1":
                raise SystemExit("Widget display did not report ready in state.")
            if state_ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("Widget touch did not report ready in state.")
        else:
            raise SystemExit(f"Could not parse ready line: {ready_line}")

        serial.write_line("PING")
        collected.append(serial.wait_for(lambda line: line == "PONG", 5, "PONG"))

        commands = [
            ("WIDGET:CI:FAIL:build red", "STATUS"),
            ("WIDGET:GITHUB:7", "STATUS"),
            ("WIDGET:ALERT:review needed", "STATUS"),
            ("TIMER:SET:25", "TIMER"),
            ("TIMER:START", "TIMER"),
            ("WIDGET:SUMMARY:AI summary ready for standup", "SUMMARY"),
            ("PAGE:HOME", "HOME"),
        ]
        for command, page in commands:
            serial.write_line(command)
            collected.append(
                serial.wait_for(
                    lambda line, page=page: line.startswith("WIDGET_PAGE")
                    and f"page={page}" in line
                    and "source=serial" in line,
                    5,
                    f"WIDGET_PAGE {page}",
                )
            )

        serial.write_line("STATE?")
        collected.append(serial.wait_for(lambda line: line.startswith("WIDGET_STATE"), 5, "WIDGET_STATE"))
        collected.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    states = parse_states(collected)
    if not states:
        raise SystemExit("No WIDGET_STATE lines captured.")
    latest = states[-1]
    pages = parse_pages(collected)

    if latest["ci"] != "FAIL":
        raise SystemExit(f"Expected ci=FAIL, saw {latest['ci']}")
    if int(latest["github"]) != 7:
        raise SystemExit(f"Expected github=7, saw {latest['github']}")
    if int(latest["alerts"]) < 1:
        raise SystemExit("Expected at least one WIDGET_ALERT.")
    if int(latest["summary_len"]) <= 0:
        raise SystemExit("Summary text was not stored.")
    if not {"STATUS", "TIMER", "SUMMARY", "HOME"}.issubset(set(pages)):
        raise SystemExit(f"Missing expected page flow, saw {pages}")

    print(
        "desk_widget_summary "
        f"states={len(states)} page_flow={','.join(pages)} "
        f"ci={latest['ci']} github={latest['github']} alerts={latest['alerts']} "
        f"timer={latest['timer']} running={latest['running']} summary_len={latest['summary_len']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
