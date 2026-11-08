"""A stub endpoint that records what a client actually sends.

The differential test needs the request body an official SDK produces, which is not the body
its documentation shows: defaults are filled in, optional fields are dropped, and the path
carries a version prefix the library under test writes separately. So the SDK is pointed at
this stub, the stub keeps the bytes, and the comparison happens afterwards.

The reply is the smallest valid answer for each vendor, so the SDK returns instead of raising
before the request has been recorded.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPENAI = {
    "id": "chatcmpl-stub",
    "object": "chat.completion",
    "created": 0,
    "model": "gpt-4o-mini",
    "choices": [
        {
            "index": 0,
            "message": {"role": "assistant", "content": "blue"},
            "finish_reason": "stop",
        }
    ],
    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
}

ANTHROPIC = {
    "id": "msg_stub",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [{"type": "text", "text": "blue"}],
    "stop_reason": "end_turn",
    "usage": {"input_tokens": 1, "output_tokens": 1},
}

GEMINI = {
    "candidates": [
        {
            "content": {"role": "model", "parts": [{"text": "blue"}]},
            "finishReason": "STOP",
            "index": 0,
        }
    ],
    "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1},
}

OLLAMA = {
    "model": "qwen2.5",
    "message": {"role": "assistant", "content": "blue"},
    "done": True,
    "done_reason": "stop",
    "prompt_eval_count": 1,
    "eval_count": 1,
}


def reply_for(path):
    if path.endswith(":generateContent"):
        return GEMINI
    if path.endswith("/messages"):
        return ANTHROPIC
    if path.endswith("/api/chat"):
        return OLLAMA
    return OPENAI


class Recorder:
    def __init__(self):
        self.requests = []
        self.lock = threading.Lock()

    def add(self, verb, path, headers, body):
        with self.lock:
            self.requests.append(
                {"verb": verb, "path": path, "headers": headers, "body": body}
            )

    def take(self):
        with self.lock:
            taken = self.requests
            self.requests = []
        return taken


def serve(recorder):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_POST(self):
            length = int(self.headers.get("content-length", "0"))
            raw = self.rfile.read(length)
            try:
                body = json.loads(raw.decode("utf-8"))
            except Exception:
                body = {"__unparsed__": raw.decode("utf-8", "replace")}
            recorder.add(
                "POST", self.path, dict(self.headers.items()), body
            )
            payload = json.dumps(reply_for(self.path)).encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            payload = b'{"object":"list","data":[]}'
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server
