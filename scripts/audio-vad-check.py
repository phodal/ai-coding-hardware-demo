#!/usr/bin/env python3
import argparse
import os
import re
import select
import subprocess
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

METRIC_RE = re.compile(r"AUDIO_METRIC .*rms=(?P<rms>\d+) peak=(?P<peak>\d+) speech=(?P<speech>[01])")


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

    def wait_for_any(self, needles: list[str], timeout: float) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                if any(needle in line for needle in needles):
                    return
        raise SystemExit(f"Timed out waiting for any of {needles!r}")


def collect_metrics(serial: SerialPort, seconds: float) -> list[dict[str, int]]:
    metrics = []
    for line in serial.read_lines(seconds):
        match = METRIC_RE.search(line)
        if match:
            metrics.append({key: int(value) for key, value in match.groupdict().items()})
    return metrics


def play_stimulus(command: str) -> None:
    print(f"> stimulus: {command}", flush=True)
    subprocess.run(command, shell=True, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate ES7210 microphone/VAD serial metrics.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--baseline-seconds", type=float, default=2.0)
    parser.add_argument("--active-seconds", type=float, default=8.0)
    parser.add_argument("--stimulus-command", default="say 'hello xiao zhi audio probe, testing microphone input'")
    parser.add_argument("--min-rms", type=int, default=5)
    parser.add_argument("--min-peak", type=int, default=20)
    parser.add_argument("--min-rms-delta", type=int, default=5)
    parser.add_argument("--min-peak-delta", type=int, default=10)
    parser.add_argument("--require-speech", action="store_true")
    args = parser.parse_args()

    serial = SerialPort(args.port, args.baud)
    try:
        serial.wait_for_any(["AUDIO_VAD_READY", "AUDIO_METRIC"], 15)
        baseline = collect_metrics(serial, args.baseline_seconds)
        play_stimulus(args.stimulus_command)
        active = collect_metrics(serial, args.active_seconds)
    finally:
        serial.close()

    if not baseline and not active:
        raise SystemExit("No AUDIO_METRIC lines captured.")

    baseline_max_rms = max((item["rms"] for item in baseline), default=0)
    baseline_max_peak = max((item["peak"] for item in baseline), default=0)
    active_max_rms = max((item["rms"] for item in active), default=0)
    active_max_peak = max((item["peak"] for item in active), default=0)
    speech_count = sum(item["speech"] for item in baseline + active)
    rms_delta = active_max_rms - baseline_max_rms
    peak_delta = active_max_peak - baseline_max_peak

    print(
        "audio_summary "
        f"baseline_max_rms={baseline_max_rms} baseline_max_peak={baseline_max_peak} "
        f"active_max_rms={active_max_rms} active_max_peak={active_max_peak} "
        f"rms_delta={rms_delta} peak_delta={peak_delta} speech_metrics={speech_count}"
    )
    if active_max_rms < args.min_rms:
        raise SystemExit(f"active_max_rms {active_max_rms} < required {args.min_rms}")
    if active_max_peak < args.min_peak:
        raise SystemExit(f"active_max_peak {active_max_peak} < required {args.min_peak}")
    if rms_delta < args.min_rms_delta:
        raise SystemExit(f"rms_delta {rms_delta} < required {args.min_rms_delta}")
    if peak_delta < args.min_peak_delta:
        raise SystemExit(f"peak_delta {peak_delta} < required {args.min_peak_delta}")
    if args.require_speech and speech_count == 0:
        raise SystemExit("No VAD speech metric observed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
