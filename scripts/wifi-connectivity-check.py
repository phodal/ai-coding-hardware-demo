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
    parser = argparse.ArgumentParser(description="Validate ESP32-S3 Wi-Fi scan and optional join over serial.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--min-networks", type=int, default=0)
    parser.add_argument("--ssid")
    parser.add_argument("--password")
    args = parser.parse_args()

    if bool(args.ssid) != bool(args.password):
        raise SystemExit("--ssid and --password must be provided together")

    lines: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        lines.extend(serial.wait_for_any(["WIFI_READY", "WIFI_SCAN", "WIFI_STATE"], 20))
        lines.extend(serial.read_lines(0.5))

        serial.write_line("PING")
        lines.extend(serial.read_lines(0.5))
        serial.write_line("STATUS?")
        lines.extend(serial.read_lines(0.5))
        serial.write_line("SCAN")
        lines.extend(serial.read_lines(8.0))
        serial.write_line("STATUS?")
        lines.extend(serial.read_lines(0.5))

        if args.ssid and args.password:
            serial.write_line(f"JOIN:{args.ssid},{args.password}", "JOIN:<redacted>")
            lines.extend(serial.read_lines(16.0))
            serial.write_line("STATUS?")
            lines.extend(serial.read_lines(0.5))

        lines.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    require(any(line == "PONG" for line in lines), "No PONG response captured.")
    require(not any(line.startswith("WIFI_ERROR") for line in lines), "WIFI_ERROR captured.")

    state = latest(lines, "WIFI_STATE ")
    scan = latest(lines, "WIFI_SCAN ")
    require(state, "No WIFI_STATE captured.")
    require(scan, "No WIFI_SCAN captured.")
    require(as_int(state, "display") == 1, f"display not ready: {state}")
    require(as_int(state, "radio") == 1, f"radio not ready: {state}")
    require(scan.get("status") == "ok", f"scan did not pass: {scan}")
    require(as_int(scan, "count", -1) >= args.min_networks, f"network count too low: {scan}")
    require(as_int(scan, "elapsed_ms") > 0, f"scan elapsed_ms invalid: {scan}")

    join = latest(lines, "WIFI_JOIN ")
    if args.ssid:
        require(join, "No WIFI_JOIN captured.")
        require(join.get("status") == "ok", f"join failed: {join}")
        require(as_int(join, "connected") == 1, f"join did not connect: {join}")

    print(
        "wifi_connectivity_summary "
        f"count={as_int(scan, 'count', -1)} "
        f"best_rssi={as_int(scan, 'best_rssi', -127)} "
        f"scan_count={as_int(scan, 'scan_count')} "
        f"connected={as_int(state, 'connected')} "
        f"ip={state.get('ip', '0.0.0.0')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
