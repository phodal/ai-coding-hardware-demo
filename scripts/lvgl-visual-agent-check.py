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

READY_RE = re.compile(r"VIS_(?:READY|PARTIAL) display=(?P<display>[01]) touch=(?P<touch>[01]) lvgl=(?P<lvgl>[01])")
STATE_RE = re.compile(
    r"VIS_STATE .*page=(?P<page>\S+) display=(?P<display>[01]) touch=(?P<touch>[01]) "
    r"lvgl=(?P<lvgl>[01]) chat=(?P<chat>\d+) cards=(?P<cards>\d+) "
    r"settings=(?P<settings>\d+) agent=(?P<agent>\d+) commands=(?P<commands>\d+)"
)
PAGE_RE = re.compile(r"VIS_PAGE page=(?P<page>\S+) source=(?P<source>\S+)")


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
            if key == "page":
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
    parser = argparse.ArgumentParser(description="Validate the LVGL visual-agent harness.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--allow-touch-missing", action="store_true")
    args = parser.parse_args()

    collected: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        ready_line = serial.wait_for(
            lambda line: line.startswith("VIS_READY")
            or line.startswith("VIS_PARTIAL")
            or line.startswith("VIS_STATE"),
            15,
            "VIS_READY",
        )
        collected.append(ready_line)
        ready = READY_RE.search(ready_line)
        state_ready = STATE_RE.search(ready_line)
        if ready:
            if ready.group("display") != "1":
                raise SystemExit("LVGL visual agent display did not report ready.")
            if ready.group("lvgl") != "1":
                raise SystemExit("LVGL visual agent did not initialize LVGL.")
            if ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("LVGL visual agent touch did not report ready.")
        elif state_ready:
            if state_ready.group("display") != "1" or state_ready.group("lvgl") != "1":
                raise SystemExit("LVGL visual agent display/LVGL did not report ready in state.")
            if state_ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("LVGL visual agent touch did not report ready in state.")

        serial.write_line("PING")
        collected.append(serial.wait_for(lambda line: line == "PONG", 5, "PONG"))
        serial.write_line("CAPS?")
        collected.append(
            serial.wait_for(
                lambda line: line.startswith("VIS_CAPS")
                and "widgets=tabview,labels,cards,settings" in line,
                5,
                "VIS_CAPS",
            )
        )

        commands = [
            ("PAGE:CHAT", "VIS_PAGE", "page=CHAT"),
            ("CHAT:user:show board status", "VIS_CHAT", "count=1"),
            ("AGENT:THINK:checking pmu imu touch", "VIS_AGENT", "event=think"),
            ("CARD:build:WARN:firmware smoke", "VIS_CARD", "count=1"),
            ("CARD:touch:OK:controller online", "VIS_CARD", "count=2"),
            ("SETTING:theme:dark", "VIS_SETTING", "count=1"),
            ("SETTING:mode:agent", "VIS_SETTING", "count=2"),
            ("PAGE:CARDS", "VIS_PAGE", "page=CARDS"),
            ("PAGE:SETTINGS", "VIS_PAGE", "page=SETTINGS"),
            ("PAGE:CHAT", "VIS_PAGE", "page=CHAT"),
        ]
        for command, prefix, needle in commands:
            serial.write_line(command)
            collected.append(
                serial.wait_for(
                    lambda line, prefix=prefix, needle=needle: line.startswith(prefix)
                    and needle in line,
                    5,
                    f"{prefix} {needle}",
                )
            )

        serial.write_line("STATE?")
        collected.append(serial.wait_for(lambda line: line.startswith("VIS_STATE"), 5, "VIS_STATE"))
        collected.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    states = parse_states(collected)
    if not states:
        raise SystemExit("No VIS_STATE lines captured.")
    latest = states[-1]
    pages = parse_pages(collected)

    if int(latest["chat"]) < 1:
        raise SystemExit("Expected at least one chat bubble.")
    if int(latest["cards"]) < 2:
        raise SystemExit(f"Expected at least two cards, saw {latest['cards']}")
    if int(latest["settings"]) < 2:
        raise SystemExit(f"Expected at least two settings, saw {latest['settings']}")
    if int(latest["agent"]) < 1:
        raise SystemExit("Expected at least one agent thought event.")
    if not {"CHAT", "CARDS", "SETTINGS"}.issubset(set(pages)):
        raise SystemExit(f"Missing expected page flow, saw {pages}")

    print(
        "lvgl_visual_agent_summary "
        f"states={len(states)} page_flow={','.join(pages)} "
        f"chat={latest['chat']} cards={latest['cards']} settings={latest['settings']} "
        f"agent={latest['agent']} commands={latest['commands']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
