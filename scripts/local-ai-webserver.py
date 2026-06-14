#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


class AiHandler(BaseHTTPRequestHandler):
    server_version = "LocalAITrigger/1.0"

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {"question": raw.decode("utf-8", errors="replace")}
        if isinstance(data, dict):
            return data
        return {"question": str(data)}

    def _answer(self, question: str, source: str) -> str:
        mode = self.server.ai_mode
        if mode == "command":
            command = self.server.ai_command
            if not command:
                raise RuntimeError("AI_TRIGGER_COMMAND is required for command mode")
            env = os.environ.copy()
            env["AI_TRIGGER_PROMPT"] = question
            env["AI_TRIGGER_SOURCE"] = source
            completed = subprocess.run(
                shlex.split(command),
                input=question,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.server.command_timeout,
                env=env,
            )
            if completed.returncode != 0:
                message = completed.stderr.strip() or f"command exited {completed.returncode}"
                raise RuntimeError(message)
            return completed.stdout.strip()[: self.server.max_chars] or "AI OK"
        return (self.server.mock_response or f"AI OK: {question}")[: self.server.max_chars]

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json(
                200,
                {
                    "ok": True,
                    "mode": self.server.ai_mode,
                    "time": int(time.time()),
                },
            )
            return
        if parsed.path in {"/ask", "/trigger"}:
            params = parse_qs(parsed.query)
            question = (params.get("question") or params.get("prompt") or ["button pressed"])[0]
            self._handle_ai(question, "board-get")
            return
        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path not in {"/ask", "/trigger"}:
            self._send_json(404, {"ok": False, "error": "not_found"})
            return
        data = self._read_json()
        question = str(data.get("question") or data.get("prompt") or "button pressed")
        source = str(data.get("source") or "board")
        self._handle_ai(question, source)

    def _handle_ai(self, question: str, source: str) -> None:
        try:
            text = self._answer(question, source)
            self.server.request_count += 1
            print(
                "local_ai_request "
                f"count={self.server.request_count} mode={self.server.ai_mode} "
                f"source={source} chars={len(text)}",
                flush=True,
            )
            self._send_json(
                200,
                {
                    "ok": True,
                    "text": text,
                    "response": text,
                    "source": source,
                    "count": self.server.request_count,
                },
            )
        except Exception as exc:
            self._send_json(500, {"ok": False, "error": str(exc)[:200]})

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"local_ai_http {self.address_string()} {fmt % args}", flush=True)


class AiServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], handler: type[AiHandler], args: argparse.Namespace) -> None:
        super().__init__(address, handler)
        self.ai_mode = args.mode
        self.ai_command = args.command or os.environ.get("AI_TRIGGER_COMMAND", "")
        self.command_timeout = args.command_timeout
        self.max_chars = args.max_chars
        self.mock_response = args.mock_response
        self.request_count = 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Local HTTP AI trigger server for the ESP32-S3 web AI button sketch.")
    parser.add_argument("--host", default=os.environ.get("LOCAL_AI_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("LOCAL_AI_PORT", "8787")))
    parser.add_argument("--mode", choices=["mock", "command"], default=os.environ.get("LOCAL_AI_MODE", "mock"))
    parser.add_argument("--command", help="Command for mode=command. Prompt is passed on stdin and AI_TRIGGER_PROMPT.")
    parser.add_argument("--command-timeout", type=float, default=float(os.environ.get("LOCAL_AI_COMMAND_TIMEOUT", "30")))
    parser.add_argument("--max-chars", type=int, default=int(os.environ.get("LOCAL_AI_MAX_CHARS", "180")))
    parser.add_argument("--mock-response", default=os.environ.get("LOCAL_AI_MOCK_RESPONSE", "AI OK from Mac"))
    args = parser.parse_args()

    server = AiServer((args.host, args.port), AiHandler, args)
    print(f"local_ai_server_ready host={args.host} port={args.port} mode={args.mode}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
