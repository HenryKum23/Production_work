# =============================================================
# File:         main.py
# Description:  Simple Python HTTP server — the application
#               that runs inside the Docker container.
#               Listens on port 8080. Nginx on the EC2 host
#               proxies port 80 traffic to this port.
# Author:       Henry Kumah
# Created:      2026-03-01
# Version:      1.0
# Usage:        python3 app/main.py
#               Runs automatically via Docker container on deploy
# =============================================================

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import datetime

PORT = 8080
HOST = "0.0.0.0"  # listen on all interfaces inside the container


class AppHandler(BaseHTTPRequestHandler):
    """Handles all incoming HTTP requests."""

    def do_GET(self):
        """Handle GET requests."""

        if self.path == "/":
            self._handle_home()

        elif self.path == "/health":
            self._handle_health()

        else:
            self._handle_not_found()

    def _handle_home(self):
        """Return a simple HTML page on the root path."""
        body = """
        <!DOCTYPE html>
        <html>
        <head><title>HFM App</title></head>
        <body>
            <h1>AWS Production Automation</h1>
            <p>Deployed via GitHub Actions CI/CD pipeline.</p>
            <p>Infrastructure provisioned by aws_setup.sh</p>
            <p>Server configured by bootstrap.sh via EC2 user-data</p>
            <p>Running inside a Docker container on port 8080</p>
            <p>Nginx proxies port 80 traffic to this container</p>
            <br>
            <p>Check server health: <a href="/health">/health</a></p>
        </body>
        </html>
        """.encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def _handle_health(self):
        """
        Health check endpoint.
        Returns JSON with status and timestamp.
        Used by the pipeline's curl verify step after deployment.
        """
        payload = {
            "status": "healthy",
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "port": PORT,
        }
        body = json.dumps(payload).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def _handle_not_found(self):
        """Return 404 for any unknown path."""
        body = b"404 Not Found"

        self.send_response(404)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        """Override default logging to include timestamp."""
        print(f"[{datetime.datetime.utcnow().isoformat()}] {format % args}")


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), AppHandler)
    print(f"=== Server started: {datetime.datetime.utcnow().isoformat()}Z ===")
    print(f"=== Listening on {HOST}:{PORT} ===")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("=== Server stopped ===")
        server.server_close()
