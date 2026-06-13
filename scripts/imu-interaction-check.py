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

    def wait_for(self, predicate, timeout: float, label: str) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                if predicate(line):
                    return line
        raise SystemExit(f"Timed out waiting for {label}")


def parse_kv(line: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for token in line.split()[1:]:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        values[key] = value
    return values


def as_int(values: dict[str, str], key: str, default: int = 0) -> int:
    try:
        return int(float(values.get(key, str(default))))
    except ValueError:
        return default


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate IMU interaction gestures over serial.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--allow-imu-missing", action="store_true")
    args = parser.parse_args()

    lines: list[str] = []
    serial = SerialPort(args.port, args.baud)
    try:
        ready = serial.wait_for(
            lambda line: line.startswith("IMU_INTERACTION_READY")
            or line.startswith("IMU_INTERACTION_PARTIAL")
            or line.startswith("IMU_INTERACTION_STATUS"),
            15,
            "IMU_INTERACTION_READY",
        )
        lines.append(ready)
        ready_values = parse_kv(ready)
        if ready.startswith("IMU_INTERACTION_READY") or ready.startswith("IMU_INTERACTION_PARTIAL"):
            require(as_int(ready_values, "display") == 1, f"display not ready: {ready}")
            require(as_int(ready_values, "imu") == 1 or args.allow_imu_missing, f"imu not ready: {ready}")

        serial.write_line("PING")
        lines.append(serial.wait_for(lambda line: line == "PONG", 5, "PONG"))
        serial.write_line("RESET")
        lines.append(serial.wait_for(lambda line: line.startswith("IMU_INTERACTION_RESET"), 5, "RESET"))
        serial.write_line("LIVE:0")
        lines.append(serial.wait_for(lambda line: line.startswith("IMU_INTERACTION_LIVE enabled=0"), 5, "LIVE:0"))
        serial.write_line("SLEEP")
        lines.append(serial.wait_for(lambda line: "name=SLEEP" in line, 5, "SLEEP event"))

        events = [
            ("WRIST_WAKE", "0.00,0.90,0.35,0.00,0.00,0.00"),
            ("SHAKE_SWITCH", "0.20,0.10,1.95,190.00,40.00,0.00"),
            ("POSE_MENU", "-0.85,0.00,0.45,0.00,0.00,0.00"),
            ("STEP", "0.00,0.00,1.42,15.00,10.00,0.00"),
        ]
        for expected_event, payload in events:
            serial.write_line(f"SAMPLE:{payload}")
            lines.append(
                serial.wait_for(
                    lambda line, expected_event=expected_event: line.startswith("IMU_EVENT")
                    and f"name={expected_event}" in line
                    and "source=serial" in line,
                    5,
                    expected_event,
                )
            )

        serial.write_line("MENU:NEXT")
        lines.append(serial.wait_for(lambda line: "name=MENU_NEXT" in line, 5, "MENU_NEXT"))
        serial.write_line("STATUS?")
        status_line = serial.wait_for(lambda line: line.startswith("IMU_INTERACTION_STATUS"), 5, "STATUS")
        lines.append(status_line)
        lines.extend(serial.read_lines(args.seconds))
    finally:
        serial.close()

    status = parse_kv(status_line)
    require(as_int(status, "display") == 1, f"display not ready in status: {status_line}")
    require(as_int(status, "imu") == 1 or args.allow_imu_missing, f"imu not ready in status: {status_line}")
    require(as_int(status, "awake") == 1, f"device did not wake: {status_line}")
    require(as_int(status, "steps") >= 1, f"step count too low: {status_line}")
    require(as_int(status, "shakes") >= 1, f"shake count too low: {status_line}")
    require(as_int(status, "wrist_wakes") >= 1, f"wrist wake count too low: {status_line}")
    require(as_int(status, "menu_changes") >= 2, f"menu changes too low: {status_line}")
    require(as_int(status, "injected") >= 4, f"injected count too low: {status_line}")

    seen_events = {
        parse_kv(line).get("name")
        for line in lines
        if line.startswith("IMU_EVENT")
    }
    required_events = {"SLEEP", "WRIST_WAKE", "SHAKE_SWITCH", "POSE_MENU", "STEP", "MENU_NEXT"}
    require(required_events.issubset(seen_events), f"missing events: {sorted(required_events - seen_events)}")

    print(
        "imu_interaction_summary "
        f"events={','.join(sorted(event for event in seen_events if event))} "
        f"steps={as_int(status, 'steps')} "
        f"shakes={as_int(status, 'shakes')} "
        f"wrist_wakes={as_int(status, 'wrist_wakes')} "
        f"menu_changes={as_int(status, 'menu_changes')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
