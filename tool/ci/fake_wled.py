"""A WLED controller as far as bambuddy talks to one, for the contract tests.

`GET /presets.json` and `GET /json/info` answer fixed bodies; `POST /json/state`
records its body, which `GET /_switched` hands back so a test can see that a
preset test reached WLED. Run in its own container on the bridge network: a
process on the host is not reachable from the server's container where the
host firewall drops that traffic.
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Ids as WLED keys them: 0 and 251 are outside the 1..250 the server keeps,
# 7 has no name and is named by its id.
PRESETS = {
    "0": {},
    "3": {"n": "Printing green"},
    "7": {"n": ""},
    "251": {"n": "Out of range"},
}
INFO = {"name": "Shelf strip", "ver": "0.15.1"}
switched = []


class Handler(BaseHTTPRequestHandler):
    def _answer(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        answers = {"/presets.json": PRESETS, "/json/info": INFO, "/_switched": switched}
        if self.path in answers:
            self._answer(answers[self.path])
        else:
            self._answer({"error": "not found"}, 404)

    def do_POST(self):
        if self.path != "/json/state":
            self._answer({"error": "not found"}, 404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        switched.append(json.loads(self.rfile.read(length) or b"null"))
        self._answer({"on": True})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
