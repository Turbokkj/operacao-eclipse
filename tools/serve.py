#!/usr/bin/env python3
"""Servidor local para testar a exportação web (MIME correto para .wasm e cabeçalhos COOP/COEP).
Uso: python3 tools/serve.py [pasta=build/web] [porta=8060]  ->  http://localhost:8060"""
import http.server
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript", ".pck": "application/octet-stream"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


if not os.path.isdir(root):
    sys.exit("Pasta '%s' não existe. Exporte o projeto primeiro (tools/export_web.sh)." % root)
os.chdir(root)
print("Servindo %s em http://localhost:%d (Ctrl+C para sair)" % (root, port))
http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
