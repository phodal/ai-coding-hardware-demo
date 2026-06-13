#!/usr/bin/env python3
import argparse
import os
import select
import subprocess
import termios
import time
import wave
from pathlib import Path


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
        os.write(self.fd, (line.rstrip() + "\n").encode("utf-8"))

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


def run_capture(audio_device: str, sample_rate: int, seconds: float, out_path: Path) -> subprocess.Popen:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "avfoundation",
        "-i",
        f"none:{audio_device}",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-t",
        f"{seconds:.3f}",
        "-y",
        str(out_path),
    ]
    print("recording:", " ".join(cmd), flush=True)
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def pcm_rms(frames: bytes, sample_width: int) -> float:
    if not frames:
        return 0.0
    count = len(frames) // sample_width
    if count == 0:
        return 0.0
    total = 0
    for i in range(count):
        start = i * sample_width
        sample = int.from_bytes(frames[start : start + sample_width], "little", signed=True)
        total += sample * sample
    return (total / count) ** 0.5


def pcm_abs_peak(frames: bytes, sample_width: int) -> int:
    if not frames:
        return 0
    count = len(frames) // sample_width
    peak = 0
    for i in range(count):
        start = i * sample_width
        sample = int.from_bytes(frames[start : start + sample_width], "little", signed=True)
        peak = max(peak, abs(sample))
    return peak


def read_window(wav: wave.Wave_read, start_seconds: float, seconds: float) -> bytes:
    framerate = wav.getframerate()
    wav.setpos(min(wav.getnframes(), int(start_seconds * framerate)))
    return wav.readframes(int(seconds * framerate))


def analyze_wav(path: Path, baseline_seconds: float, active_offset: float, active_seconds: float) -> dict[str, float]:
    with wave.open(str(path), "rb") as wav:
        if wav.getnchannels() != 1:
            raise SystemExit(f"Expected mono WAV, got {wav.getnchannels()} channels")
        sample_width = wav.getsampwidth()
        baseline = read_window(wav, 0.0, baseline_seconds)
        active = read_window(wav, active_offset, active_seconds)

    baseline_rms = pcm_rms(baseline, sample_width)
    active_rms = pcm_rms(active, sample_width)
    baseline_peak = pcm_abs_peak(baseline, sample_width)
    active_peak = pcm_abs_peak(active, sample_width)
    rms_delta = active_rms - baseline_rms
    peak_delta = active_peak - baseline_peak
    ratio = active_rms / max(1.0, baseline_rms)
    return {
        "baseline_rms": baseline_rms,
        "active_rms": active_rms,
        "baseline_peak": baseline_peak,
        "active_peak": active_peak,
        "rms_delta": rms_delta,
        "peak_delta": peak_delta,
        "ratio": ratio,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate ES8311 speaker output through host microphone capture.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--audio-device", default="1")
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--baseline-seconds", type=float, default=2.0)
    parser.add_argument("--active-seconds", type=float, default=5.0)
    parser.add_argument("--settle-seconds", type=float, default=0.5)
    parser.add_argument("--out", required=True)
    parser.add_argument("--min-active-rms", type=float, default=500.0)
    parser.add_argument("--min-rms-delta", type=float, default=200.0)
    parser.add_argument("--min-ratio", type=float, default=1.8)
    args = parser.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    total_seconds = args.baseline_seconds + args.settle_seconds + args.active_seconds

    serial = SerialPort(args.port, args.baud)
    try:
      serial.wait_for_any(["SPEAKER_OUTPUT_READY", "SPEAKER_OUTPUT_HEARTBEAT audio=ready"], 15)
      capture = run_capture(args.audio_device, args.sample_rate, total_seconds, out_path)
      try:
          time.sleep(args.baseline_seconds)
          serial.write_line("PLAY")
          serial.wait_for_any(["SPEAKER_TONE_END"], args.active_seconds + 5)
          stdout, stderr = capture.communicate(timeout=args.settle_seconds + args.active_seconds + 5)
      finally:
          if capture.poll() is None:
              capture.terminate()
              stdout, stderr = capture.communicate(timeout=5)
      if capture.returncode != 0:
          raise SystemExit(
              f"ffmpeg audio capture failed with {capture.returncode}:\n"
              f"{stdout.decode(errors='replace')}\n{stderr.decode(errors='replace')}"
          )
    finally:
        serial.close()

    summary = analyze_wav(out_path, args.baseline_seconds, args.baseline_seconds + args.settle_seconds, args.active_seconds)
    print(
        "speaker_summary "
        f"baseline_rms={summary['baseline_rms']:.1f} active_rms={summary['active_rms']:.1f} "
        f"baseline_peak={summary['baseline_peak']:.0f} active_peak={summary['active_peak']:.0f} "
        f"rms_delta={summary['rms_delta']:.1f} peak_delta={summary['peak_delta']:.0f} "
        f"ratio={summary['ratio']:.2f} wav={out_path}"
    )
    if summary["active_rms"] < args.min_active_rms:
        raise SystemExit(f"active_rms {summary['active_rms']:.1f} < required {args.min_active_rms:.1f}")
    if summary["rms_delta"] < args.min_rms_delta:
        raise SystemExit(f"rms_delta {summary['rms_delta']:.1f} < required {args.min_rms_delta:.1f}")
    if summary["ratio"] < args.min_ratio:
        raise SystemExit(f"ratio {summary['ratio']:.2f} < required {args.min_ratio:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
