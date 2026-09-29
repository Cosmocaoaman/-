"""Exercise the compiled Rime plugin with deterministic HTTP fault injection."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ai" / "scripts"))
from mock_server import Handler, ThreadingHTTPServer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=["x64", "x86"], default="x64")
    args = parser.parse_args()
    exe = ROOT / "librime" / f"build-{args.arch}" / "bin" / "local_ai_probe.exe"
    (ROOT / "ai" / "logs").mkdir(parents=True, exist_ok=True)
    if not exe.is_file():
        parser.error(f"Build the {args.arch} engine first: {exe}")
    server = ThreadingHTTPServer(("127.0.0.1", 18080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results = []
    try:
        with tempfile.TemporaryDirectory(prefix="rime-ai-", dir=ROOT / "ai" / "logs") as user:
            for backend, scenario in [("success", "success"), ("success", "cancel"),
                                      ("success", "destroy"), ("error", "error"),
                                      ("malformed", "error"), ("timeout", "error")]:
                Handler.mode = backend
                started = time.perf_counter()
                result = subprocess.run([str(exe), str(ROOT / "ai" / "rime-data"), user, scenario],
                                        capture_output=True, timeout=35)
                output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
                record = {"backend": backend, "scenario": scenario, "returncode": result.returncode,
                          "seconds": round(time.perf_counter()-started, 3), "output": output[-6000:]}
                results.append(record)
                print(f"{backend}/{scenario}: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
                if result.returncode:
                    print(output[-6000:])
                time.sleep(0.4)
    finally:
        server.shutdown(); server.server_close(); thread.join()
    (ROOT / "ai" / "logs" / f"integration-{args.arch}.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return int(any(r["returncode"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
