#!/usr/bin/env bash
# 构建并启动桌面宠物
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$ROOT/build.sh"

pkill -x HappyPet 2>/dev/null || true
open "$ROOT/build/HappyPet.app"
echo "🐾 已启动,菜单栏爪印图标里可以退出"