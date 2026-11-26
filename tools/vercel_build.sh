#!/usr/bin/env bash
# Build do jogo na própria Vercel: baixa o Godot 4.3 (headless) + template de exportação Web e exporta para build/web.
# Variável opcional no painel da Vercel: GAME_SERVER_URL=wss://seu-servidor-de-partidas  (vira o servidor padrão do jogo).
set -euo pipefail
V="${GODOT_VERSION:-4.3}"
BASE="https://github.com/godotengine/godot/releases/download/${V}-stable"
cd "$(dirname "$0")/.."
# Recursos de áudio e texturas são gerados localmente no build; não armazenamos blobs binários no repositório.
python3 -m pip install --quiet --disable-pip-version-check numpy pillow
python3 tools/gen_audio.py
python3 tools/gen_textures.py
BIN=".godot-bin"; mkdir -p "$BIN"
if [ ! -x "$BIN/godot" ]; then
  curl -fsSL -o "$BIN/godot.zip" "$BASE/Godot_v${V}-stable_linux.x86_64.zip"
  python3 - "$BIN" "$V" <<'PY'
import sys, zipfile, os
b, v = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(f"{b}/godot.zip"); z.extract(f"Godot_v{v}-stable_linux.x86_64", b)
os.rename(f"{b}/Godot_v{v}-stable_linux.x86_64", f"{b}/godot"); os.chmod(f"{b}/godot", 0o755)
PY
fi
TPL="$HOME/.local/share/godot/export_templates/${V}.stable"
if [ ! -f "$TPL/web_nothreads_release.zip" ]; then
  curl -fsSL -o "$BIN/tpl.tpz" "$BASE/Godot_v${V}-stable_export_templates.tpz"
  mkdir -p "$TPL"
  python3 - "$BIN" "$TPL" <<'PY'
import sys, zipfile, shutil
b, tpl = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(f"{b}/tpl.tpz")
for n in ("templates/web_nothreads_release.zip", "templates/web_nothreads_debug.zip", "templates/version.txt"):
    with z.open(n) as src, open(f"{tpl}/{n.split('/')[-1]}", "wb") as dst: shutil.copyfileobj(src, dst)
PY
  rm -f "$BIN/tpl.tpz"
fi
if [ -n "${GAME_SERVER_URL:-}" ]; then printf '%s\n' "$GAME_SERVER_URL" > server_url.txt; fi
"$BIN/godot" --headless --path . --import 2>&1 | tail -40 || true
mkdir -p build/web
"$BIN/godot" --headless --path . --export-release "Web" build/web/index.html 2>&1 | tail -60
test -f build/web/index.html || { echo "ERRO: a exportação não gerou build/web/index.html (veja os erros acima)"; exit 1; }
ls -la build/web
