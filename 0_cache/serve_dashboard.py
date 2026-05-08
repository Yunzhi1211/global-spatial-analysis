#!/usr/bin/env python3
import http.server
import socketserver
import webbrowser
import os

PORT = 8000
os.chdir(os.path.dirname(os.path.abspath(__file__)))

print(f"Starting server at http://localhost:{PORT}")
print("Dashboard available at: http://localhost:8000/3_output/10_fancy_dashboard.html")
print("Test page available at: http://localhost:8000/test_dashboard.html")

Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()