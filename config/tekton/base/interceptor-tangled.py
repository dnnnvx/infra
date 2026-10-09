"""Tekton Triggers ClusterInterceptor: verify Tangled webhook signatures.

Tangled signs the raw body as `X-Tangled-Signature-256: sha256=<hex hmac>`,
the same scheme as GitHub, but the built-in github interceptor only reads
`X-Hub-Signature-256`. The EventListener POSTs an InterceptorRequest JSON
({"body": <raw body string>, "header": {name: [values]}, ...}) and expects an
InterceptorResponse ({"continue": bool, "status": {...}}) back.
"""

import hashlib
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

with open(os.environ["WEBHOOK_SECRET_FILE"], "rb") as f:
    SECRET = f.read().strip()

# google.golang.org/grpc/codes, which Tekton uses for status.code
UNAUTHENTICATED = 16
INVALID_ARGUMENT = 3


def verify(request):
    headers = {k.lower(): v for k, v in (request.get("header") or {}).items()}
    signature = (headers.get("x-tangled-signature-256") or [""])[0]
    if not signature:
        return False, INVALID_ARGUMENT, "missing X-Tangled-Signature-256 header"
    body = (request.get("body") or "").encode()
    expected = "sha256=" + hmac.new(SECRET, body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return False, UNAUTHENTICATED, "X-Tangled-Signature-256 does not match"
    return True, 0, ""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # readiness/liveness
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        try:
            request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            ok, code, message = verify(request)
        except (ValueError, TypeError) as e:
            ok, code, message = False, INVALID_ARGUMENT, f"bad interceptor request: {e}"
        response = {"continue": ok}
        if not ok:
            response["status"] = {"code": code, "message": message}
        payload = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
