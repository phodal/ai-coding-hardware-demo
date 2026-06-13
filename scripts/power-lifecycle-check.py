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

    def write_line(self, line: str) -> None:
        print(f"> {line}", flush=True)
        os.write(self.fd, (line + "\n").encode("utf-8"))

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
    parser = argparse.ArgumentParser(description="Validate power lifecycle serial controls.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--min-system-mv", type=int, default=2500)
    parser.add_argument("--require-battery", action="store_true")
    parser.add_argument("--min-batt-mv", type=int, default=3000)
    args = parser.parse_args()

    lines: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        lines.extend(serial.wait_for_any(["POWER_READY", "POWER_PARTIAL", "POWER_STATE", "POWER_SAMPLE"], 15))
        lines.extend(serial.read_lines(0.8))

        commands = [
            ("PING", 0.4),
            ("PROFILE?", 0.4),
            ("SAMPLE?", 0.4),
            ("MODE:DIM", 0.6),
            ("MODE:STANDBY", 0.6),
            ("MODE:ACTIVE", 0.6),
            ("BRIGHT:96", 0.6),
            ("CAPACITY:500", 0.4),
            ("LOAD:180,60,15", 0.4),
            ("SAMPLE?", 0.4),
            ("STATE?", 0.4),
        ]
        for command, wait_seconds in commands:
            serial.write_line(command)
            lines.extend(serial.read_lines(wait_seconds))

        lines.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    require(any(line == "PONG" for line in lines), "No PONG response captured.")
    require(not any(line.startswith("POWER_ERROR") for line in lines), "POWER_ERROR captured.")

    state = latest(lines, "POWER_STATE ")
    profile = latest(lines, "POWER_PROFILE ")
    sample = latest(lines, "POWER_SAMPLE ")
    require(state, "No POWER_STATE captured.")
    require(profile, "No POWER_PROFILE captured.")
    require(sample, "No POWER_SAMPLE captured.")

    seen_modes = {
        parse_kv(line).get("mode")
        for line in lines
        if line.startswith("POWER_MODE ")
    }
    require({"DIM", "STANDBY", "ACTIVE"}.issubset(seen_modes), f"Missing mode transitions: {seen_modes}")

    require(as_int(state, "display") == 1, f"display not ready in state: {state}")
    require(as_int(state, "pmu") == 1, f"pmu not ready in state: {state}")
    require(state.get("mode") == "ACTIVE", f"final mode is not ACTIVE: {state}")
    require(as_int(state, "brightness") == 96, f"final brightness is not 96: {state}")
    require(as_int(state, "mode_changes") >= 3, f"mode_changes too low: {state}")
    require(as_int(state, "wake_count") >= 1, f"wake_count too low: {state}")

    require(as_int(profile, "capacity_mah") == 500, f"capacity_mah not applied: {profile}")
    require(as_int(profile, "active_ma") == 180, f"active_ma not applied: {profile}")
    require(as_int(profile, "dim_ma") == 60, f"dim_ma not applied: {profile}")
    require(as_int(profile, "standby_ma") == 15, f"standby_ma not applied: {profile}")

    require(as_int(sample, "pmu") == 1, f"sample pmu not ready: {sample}")
    require(as_int(sample, "system_mv") >= args.min_system_mv, f"system_mv too low: {sample}")
    require(as_int(sample, "estimate_min") >= 0, f"estimate_min negative: {sample}")
    require(as_int(sample, "sample_count") >= 2, f"sample_count too low: {sample}")

    if args.require_battery:
        battery_samples = [
            parse_kv(line)
            for line in lines
            if line.startswith("POWER_SAMPLE ") and parse_kv(line).get("battery_connected") == "1"
        ]
        require(battery_samples, "No connected battery sample captured.")
        max_batt_mv = max(as_int(item, "batt_mv") for item in battery_samples)
        require(max_batt_mv >= args.min_batt_mv, f"max_batt_mv {max_batt_mv} < {args.min_batt_mv}")

    print(
        "power_lifecycle_summary "
        f"modes={','.join(sorted(mode for mode in seen_modes if mode))} "
        f"system_mv={as_int(sample, 'system_mv')} "
        f"vbus_mv={as_int(sample, 'vbus_mv')} "
        f"batt_mv={as_int(sample, 'batt_mv')} "
        f"battery_connected={as_int(sample, 'battery_connected')} "
        f"estimate_min={as_int(sample, 'estimate_min')} "
        f"mode_changes={as_int(state, 'mode_changes')} "
        f"wake_count={as_int(state, 'wake_count')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
