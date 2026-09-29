"""Protocol fixture, NOT an AI model. Binds only to loopback; never logs input text."""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    mode = "success"

    def log_message(self, *_):
        pass

    def send_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"mode": "mock", "model_loaded": False})
        else:
            self.send_json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self.send_json(404, {"error": "not_found"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 16384:
                return self.send_json(413, {"error": "body_size"})
            body = json.loads(self.rfile.read(size))
            assert body["stream"] is False
            assert body["model"] == "qwen3.5-0.8b"
            assert isinstance(body["messages"][-1]["content"], str)
        except (ValueError, KeyError, AssertionError, TypeError):
            return self.send_json(400, {"error": "invalid_request"})
        mode = self.mode
        time.sleep(8 if mode == "timeout" else 0.25)
        if mode == "error":
            return self.send_json(503, {"error": "mock_unavailable"})
        if mode == "malformed":
            return self.send_json(200, {"unexpected": True})
        text = "[MOCK]，很高兴认识你。"
        self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": text}}]})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--mode", choices=["success", "error", "malformed", "timeout"], default="success")
    args = parser.parse_args()
    Handler.mode = args.mode
    print(f"MOCK ONLY: http://127.0.0.1:{args.port}; no model loaded", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
