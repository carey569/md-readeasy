#!/usr/bin/env bash
# 重新拉取前端渲染依赖到 Resources/web/vendor（产物已提交到仓库，平时构建不需要运行）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/web/vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
npm init -y >/dev/null
npm install --no-audit --no-fund \
  markdown-it@15.0.3 \
  markdown-it-footnote@4.0.0 \
  markdown-it-texmath@1.0.0 \
  @highlightjs/cdn-assets@11.11.1 \
  katex@0.16.25 \
  mermaid@11.12.1 >/dev/null

M="$TMP/node_modules"
rm -rf "$DEST"
mkdir -p "$DEST/katex/fonts"

cp "$M/markdown-it/dist/browser/markdown-it.umd.min.js" "$DEST/markdown-it.min.js"
cp "$M/markdown-it-footnote/dist/markdown-it-footnote.min.js" "$DEST/"
cp "$M/markdown-it-texmath/texmath.js" "$DEST/"
cat "$M/@highlightjs/cdn-assets/highlight.min.js" \
    "$M/@highlightjs/cdn-assets/languages/dockerfile.min.js" \
    "$M/@highlightjs/cdn-assets/languages/nginx.min.js" \
    "$M/@highlightjs/cdn-assets/languages/powershell.min.js" \
    "$M/@highlightjs/cdn-assets/languages/protobuf.min.js" > "$DEST/highlight.min.js"
cp "$M/katex/dist/katex.min.js" "$M/katex/dist/katex.min.css" "$DEST/katex/"
cp "$M"/katex/dist/fonts/*.woff2 "$DEST/katex/fonts/"
cp "$M/mermaid/dist/mermaid.min.js" "$DEST/"

echo "vendor 已更新：$DEST"
du -sh "$DEST"
