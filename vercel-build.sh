#!/usr/bin/env bash
set -euo pipefail
mkdir -p .cache/operacao-eclipse
cat payload/part-*.b64 | base64 -d > .cache/operacao-eclipse/source.tar.xz
tar -xJf .cache/operacao-eclipse/source.tar.xz
cd operacao-eclipse
bash tools/vercel_build.sh
