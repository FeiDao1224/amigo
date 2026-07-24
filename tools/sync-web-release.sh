#!/bin/bash
# 将指定 GitHub Release 的 Amigo.zip 同步到 Vercel 静态下载目录。
# 用法：tools/sync-web-release.sh [tag]，默认取最新正式版。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-$(gh release view --repo FeiDao1224/amigo --json tagName --jq .tagName)}"
DEST="$ROOT/web/downloads"

mkdir -p "$DEST"
gh release download "$TAG" \
  --repo FeiDao1224/amigo \
  --pattern Amigo.zip \
  --dir "$DEST" \
  --clobber

echo "已同步 $TAG:"
shasum -a 256 "$DEST/Amigo.zip"
