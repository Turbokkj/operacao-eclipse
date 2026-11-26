#!/usr/bin/env bash
# Exporta o jogo para HTML5/WebAssembly (single-thread). Requer Godot 4.3+ e os export templates instalados.
# Uso: GODOT=/caminho/godot tools/export_web.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p build/web
echo ">> Importando recursos (primeira vez / projeto limpo)..."
"$GODOT" --headless --path . --import || true
echo ">> Exportando preset 'Web' para build/web/index.html ..."
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
echo ">> Pronto. Teste com: python3 tools/serve.py build/web 8060"
