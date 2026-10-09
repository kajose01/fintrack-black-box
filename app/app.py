import json, os, random, time, urllib.request, urllib.error
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE = os.getenv("SERVICE", "app")
VERSION = os.getenv("VERSION", "v1")
UPSTREAM = os.getenv("UPSTREAM", "")
FAIL_RATE = float(os.getenv("FAIL_RATE", "0"))            # fault knob: fraction of requests returning 500
DELAY_MS = int(os.getenv("DELAY_MS", "0"))                # latency knob
FEATURE_NEW_FLOW = os.getenv("FEATURE_NEW_FLOW", "false").lower() == "true"   # feature toggle via env var
AUTO_LEAK_MB = int(os.getenv("AUTO_LEAK_MB", "0"))        # simulates a memory leak (OOMKilled demo)
TRACE_HEADERS = ["x-request-id", "x-b3-traceid", "x-b3-spanid", "x-b3-parentspanid",
                 "x-b3-sampled", "x-b3-flags", "b3", "traceparent", "tracestate"]
_leak = []

def leak(mb):
    _leak.append(bytearray(b"x") * (mb * 1024 * 1024))

if AUTO_LEAK_MB:
    leak(AUTO_LEAK_MB)

class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        print(json.dumps({"svc": SERVICE, "ver": VERSION, "msg": fmt % a}), flush=True)

    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/healthz":
            return self._send(200, {"ok": True})
        if u.path == "/leak":
            leak(int(parse_qs(u.query).get("mb", ["10"])[0]))
            return self._send(200, {"leaked_mb": sum(len(x) for x in _leak) // 1048576})
        if DELAY_MS:
            time.sleep(DELAY_MS / 1000)
        if random.random() < FAIL_RATE:
            return self._send(500, {"service": SERVICE, "version": VERSION, "error": "injected failure"})
        body = {"service": SERVICE, "version": VERSION}
        if FEATURE_NEW_FLOW:
            body["feature_new_flow"] = True
        if UPSTREAM:
            hdrs = {h: self.headers[h] for h in TRACE_HEADERS if self.headers.get(h)}
            try:
                with urllib.request.urlopen(urllib.request.Request(UPSTREAM, headers=hdrs), timeout=2.5) as r:
                    body["upstream"] = json.load(r)
            except urllib.error.HTTPError as e:
                return self._send(e.code, {"service": SERVICE, "error": f"upstream returned {e.code}"})
            except Exception as e:
                return self._send(502, {"service": SERVICE, "error": f"upstream unreachable: {e}"})
        self._send(200, body)

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
