#!/usr/bin/env bash
# 构建 HappyPet.app(纯 swiftc,无需 Xcode 工程)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/HappyPet.app"
ARCH="$(uname -m)"
FIX="$ROOT/build/.toolchain-fix"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FIX"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# 拷贝素材(人物立绘 / 照片 / 情话 / 配置),缺失也不影响构建
if [[ -d "$ROOT/Resources/Assets" ]]; then
  ditto "$ROOT/Resources/Assets" "$APP/Contents/Resources/Assets"
fi

EXTRA_FLAGS=()

# ---------------------------------------------------------------------------
# 兼容修复:部分机器的 Command Line Tools 里同时残留
#   usr/include/swift/module.modulemap 和 usr/include/swift/bridging.modulemap
# 两者都定义 module SwiftBridging,导致 clang 报
#   "redefinition of module 'SwiftBridging'"
# 这里用虚拟文件系统(VFS overlay)把陈旧的 module.modulemap 映射成空文件,
# 不改动任何系统文件,只在本次编译生效。
# ---------------------------------------------------------------------------
SWIFT_INC="$(xcrun --find clang 2>/dev/null | xargs dirname | xargs dirname)/include/swift"
if [[ -f "$SWIFT_INC/module.modulemap" && -f "$SWIFT_INC/bridging.modulemap" ]]; then
  echo "🩹 检测到重复的 SwiftBridging modulemap,启用 VFS overlay 规避"
  : > "$FIX/empty.modulemap"
  cat > "$FIX/overlay.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": false,
  "roots": [
    {
      "type": "directory",
      "name": "$SWIFT_INC",
      "contents": [
        {
          "type": "file",
          "name": "module.modulemap",
          "external-contents": "$FIX/empty.modulemap"
        }
      ]
    }
  ]
}
EOF
  EXTRA_FLAGS+=(-vfsoverlay "$FIX/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$FIX/overlay.yaml")
fi

echo "🔨 编译中 (${ARCH})..."
swiftc -O \
  -target "${ARCH}-apple-macosx13.0" \
  ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  "$ROOT/Sources/HappyPet/"*.swift \
  -o "$APP/Contents/MacOS/HappyPet"

# 本地临时签名,避免首次运行被拦
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ 构建完成: $APP"
echo "   运行: open \"$APP\"   或   ./run.sh"