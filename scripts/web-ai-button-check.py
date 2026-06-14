#!/usr/bin/env python3
import argparse
import os
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

    def write_line(self, line: str, display_line: str | None = None) -> None:
        print(f"> {display_line or line}", flush=True)
        os.write(self.fd, (line.rstrip("\n") + "\n").encode("utf-8"))

    def read_lines(self, timeout: float) -> list[str]:
        deadline = time.time() + timeout
        lines: list[str] = []
        while time.time() < deadline:
            readable, _, _ = select.select([self.fd], [], [], 0.1)
            if not readable:
                continue
            try:
                chunk = os.read(self.fd, 4096)
            except BlockingIOError:
                continue
            if not chunk:
                continue
            self.buffer += chunk
            while b"\n" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\n", 1)
                line = raw.decode("utf-8", errors="replace").strip()
                if line:
                    print(f"< {line}", flush=True)
                    lines.append(line)
        return lines

    def wait_for_any(self, needles: list[str], timeout: float) -> list[str]:
        deadline = time.time() + timeout
        captured: list[str] = []
        while time.time() < deadline:
            lines = self.read_lines(min(0.5, max(0.0, deadline - time.time())))
            captured.extend(lines)
            if any(any(needle in line for needle in needles) for line in lines):
                return captured
        raise SystemExit(f"Timed out waiting for any of {needles!r}")


def parse_kv(line: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for token in line.split()[1:]:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        values[key] = value
    return values


def latest(lines: list[str], prefix: str) -> dict[str, str]:
    for line in reversed(lines):
        if line.startswith(prefix):
            return parse_kv(line)
    return {}


def as_int(values: dict[str, str], key: str, default: int = 0) -> int:
    try:
        return int(float(values.get(key, str(default))))
    except ValueError:
        return default


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the web_ai_button sketch against a local HTTP AI server.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--ssid", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--question", default="touch button")
    parser.add_argument("--expect", default="AI OK")
    parser.add_argument("--timeout", type=float, default=35)
    args = parser.parse_args()

    lines: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        lines.extend(serial.wait_for_any(["WEB_AI_READY", "WEB_AI_PARTIAL", "WEB_AI_STATE"], 20))
        serial.write_line("PING")
        lines.extend(serial.read_lines(0.5))
        serial.write_line("STATE?")
        lines.extend(serial.read_lines(0.5))

        serial.write_line(
            f"CONFIG:{args.ssid},{args.password},{args.endpoint}",
            f"CONFIG:<redacted>,<redacted>,{args.endpoint}",
        )
        lines.extend(serial.wait_for_any(["WEB_AI_WIFI status="], args.timeout))
        lines.extend(serial.read_lines(0.5))

        serial.write_line(f"TRIGGER:{args.question}")
        lines.extend(serial.wait_for_any(["WEB_AI_RESPONSE status="], args.timeout))
        serial.write_line("STATE?")
        lines.extend(serial.read_lines(0.5))
    finally:
        serial.close()

    require(any(line == "PONG" for line in lines), "No PONG response captured.")
    ready = latest(lines, "WEB_AI_STATE ")
    wifi = latest(lines, "WEB_AI_WIFI ")
    response = latest(lines, "WEB_AI_RESPONSE ")
    require(wifi.get("status") == "ok", f"Wi-Fi join failed: {wifi}")
    require(as_int(wifi, "connected") == 1, f"Wi-Fi did not connect: {wifi}")
    require(response.get("status") == "ok", f"AI response failed: {response}")
    require(args.expect in " ".join(lines), f"Expected {args.expect!r} in serial output.")

    print(
        "web_ai_button_summary "
        f"connected={as_int(wifi, 'connected')} "
        f"ip={wifi.get('ip', '0.0.0.0')} "
        f"triggers={as_int(ready, 'triggers')} "
        f"touch={as_int(ready, 'touch')} "
        f"expect={args.expect!r}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
