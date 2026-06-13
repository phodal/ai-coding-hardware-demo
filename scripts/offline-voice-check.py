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

READY_RE = re.compile(r"VOICE_(?:READY|PARTIAL) display=(?P<display>[01]) touch=(?P<touch>[01]) commands=(?P<commands>\d+)")
STATE_RE = re.compile(
    r"VOICE_STATE .*page=(?P<page>\S+) display=(?P<display>[01]) touch=(?P<touch>[01]) "
    r"wake=(?P<wake>[01]) mode=(?P<mode>\S+) commands=(?P<commands>\d+) "
    r"recognized=(?P<recognized>\d+) rejected=(?P<rejected>\d+) actions=(?P<actions>\d+) "
    r"light=(?P<light>[01]) asleep=(?P<asleep>[01]) last=(?P<last>\S+)"
)
PAGE_RE = re.compile(r"VOICE_PAGE page=(?P<page>\S+) source=(?P<source>\S+)")


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
            if key in {"page", "mode", "last"}:
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
    parser = argparse.ArgumentParser(description="Validate the offline voice-control serial harness.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--allow-touch-missing", action="store_true")
    args = parser.parse_args()

    collected: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        ready_line = serial.wait_for(
            lambda line: line.startswith("VOICE_READY")
            or line.startswith("VOICE_PARTIAL")
            or line.startswith("VOICE_STATE"),
            15,
            "VOICE_READY",
        )
        collected.append(ready_line)
        ready = READY_RE.search(ready_line)
        state_ready = STATE_RE.search(ready_line)
        if ready:
            if ready.group("display") != "1":
                raise SystemExit("Offline voice display did not report ready.")
            if ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("Offline voice touch did not report ready.")
            if int(ready.group("commands")) < 4:
                raise SystemExit("Offline voice harness reported too few commands.")
        elif state_ready:
            if state_ready.group("display") != "1":
                raise SystemExit("Offline voice display did not report ready in state.")
            if state_ready.group("touch") != "1" and not args.allow_touch_missing:
                raise SystemExit("Offline voice touch did not report ready in state.")

        serial.write_line("PING")
        collected.append(serial.wait_for(lambda line: line == "PONG", 5, "PONG"))
        serial.write_line("MODEL?")
        collected.append(
            serial.wait_for(
                lambda line: line.startswith("VOICE_MODEL")
                and "wake_engine=WakeNet" in line
                and "command_engine=MultiNet" in line,
                5,
                "VOICE_MODEL",
            )
        )

        commands = [
            ("CMD:LIGHT_ON", "VOICE_REJECT", "reason=not_awake"),
            ("WAKE:hi esp", "VOICE_WAKE", "engine=WakeNet"),
            ("CMD:LIGHT_ON", "VOICE_ACTION", "action=LIGHT:ON"),
            ("WAKE:hi esp", "VOICE_WAKE", "engine=WakeNet"),
            ("CMD:NEXT_PAGE", "VOICE_ACTION", "action=UI:NEXT_PAGE"),
            ("ADDCMD:FOCUS:focus mode:UI:FOCUS", "VOICE_COMMAND_ADDED", "id=FOCUS"),
            ("MODE:CONTINUOUS", "VOICE_MODE", "mode=CONTINUOUS"),
            ("CMD:FOCUS", "VOICE_ACTION", "action=UI:FOCUS"),
            ("CMD:SLEEP", "VOICE_ACTION", "action=POWER:SLEEP"),
            ("WAKE:hi esp", "VOICE_WAKE", "engine=WakeNet"),
            ("CMD:LIGHT_OFF", "VOICE_ACTION", "action=LIGHT:OFF"),
            ("PAGE:COMMANDS", "VOICE_PAGE", "page=COMMANDS"),
            ("PAGE:STATE", "VOICE_PAGE", "page=STATE"),
            ("PAGE:LOG", "VOICE_PAGE", "page=LOG"),
            ("PAGE:HOME", "VOICE_PAGE", "page=HOME"),
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
        collected.append(serial.wait_for(lambda line: line.startswith("VOICE_STATE"), 5, "VOICE_STATE"))
        collected.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    states = parse_states(collected)
    if not states:
        raise SystemExit("No VOICE_STATE lines captured.")
    latest = states[-1]
    pages = parse_pages(collected)

    if int(latest["commands"]) < 5:
        raise SystemExit(f"Expected at least 5 commands, saw {latest['commands']}")
    if int(latest["recognized"]) < 5:
        raise SystemExit(f"Expected at least 5 recognized commands, saw {latest['recognized']}")
    if int(latest["rejected"]) < 1:
        raise SystemExit("Expected one rejected command before wake.")
    if int(latest["actions"]) < 5:
        raise SystemExit(f"Expected at least 5 actions, saw {latest['actions']}")
    if int(latest["light"]) != 0:
        raise SystemExit("Expected light to be OFF after LIGHT_OFF.")
    if str(latest["mode"]) != "CONTINUOUS":
        raise SystemExit(f"Expected continuous mode, saw {latest['mode']}")
    if not {"COMMANDS", "STATE", "LOG", "HOME"}.issubset(set(pages)):
        raise SystemExit(f"Missing expected page flow, saw {pages}")

    print(
        "offline_voice_summary "
        f"states={len(states)} page_flow={','.join(pages)} commands={latest['commands']} "
        f"recognized={latest['recognized']} rejected={latest['rejected']} actions={latest['actions']} "
        f"mode={latest['mode']} light={latest['light']} asleep={latest['asleep']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
