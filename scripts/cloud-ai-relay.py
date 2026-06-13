#!/usr/bin/env python3
import argparse
import json
import os
import select
import termios
import time
import urllib.request


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
        self._configure(baud)
        self.buffer = b""

    def _configure(self, baud: int) -> None:
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
                    lines.append(line)
                    print(f"< {line}", flush=True)
        return lines

    def wait_for(self, needle: str, timeout: float) -> str:
        deadline = time.time() + timeout
        seen: list[str] = []
        while time.time() < deadline:
            for line in self.read_lines(min(0.5, max(0.0, deadline - time.time()))):
                seen.append(line)
                if needle in line:
                    return line
        raise SystemExit(f"Timed out waiting for {needle!r}. Last lines: {seen[-8:]}")


def http_response(endpoint: str, question: str, timeout: float) -> str:
    payload = json.dumps({"question": question}).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = json.load(response)
    text = data.get("text") or data.get("response") or data.get("answer")
    if not text:
        raise SystemExit(f"HTTP response did not include text/response/answer: {data}")
    return str(text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Host relay for the cloud_ai_terminal sketch.")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--mode", choices=["mock", "http"], default="mock")
    parser.add_argument("--endpoint", help="HTTP endpoint for mode=http. Expects JSON with text/response/answer.")
    parser.add_argument("--question", default="hello")
    parser.add_argument("--response", default="AI OK")
    parser.add_argument("--expect", default="AI_DISPLAYED")
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()

    if args.mode == "http" and not args.endpoint:
        raise SystemExit("--endpoint is required for mode=http")

    serial = SerialPort(args.port, args.baud)
    try:
        serial.wait_for("CLOUD_AI_READY", args.timeout)
        print("> PING", flush=True)
        serial.write_line("PING")
        serial.wait_for("PONG", 5)

        print(f"> ASK:{args.question}", flush=True)
        serial.write_line(f"ASK:{args.question}")
        serial.wait_for("ASK_RX", 5)

        answer = http_response(args.endpoint, args.question, args.timeout) if args.mode == "http" else args.response
        print(f"> AI:{answer}", flush=True)
        serial.write_line(f"AI:{answer}")
        serial.wait_for(args.expect, 5)
    finally:
        serial.close()

    print(json.dumps({"status": "ok", "mode": args.mode, "response": args.response}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
