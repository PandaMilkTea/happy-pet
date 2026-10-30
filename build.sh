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

BIN="$APP/Contents/MacOS/HappyPet"

# 编译单个架构到指定输出路径
compile_arch() {
  local arch="$1" out="$2"
  swiftc -O \
    -target "${arch}-apple-macosx13.0" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    -framework AppKit \
    -framework SwiftUI \
    -framework AVFoundation \
    "$ROOT/Sources/HappyPet/"*.swift \
    -o "$out"
}

# UNIVERSAL=1 时产出 arm64 + x86_64 双架构,送给 Intel Mac 也能打开。
# 平时本地开发只编当前架构,快一半。
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  echo "🔨 编译中 (universal: arm64 + x86_64)..."
  compile_arch arm64 "$FIX/HappyPet-arm64"
  compile_arch x86_64 "$FIX/HappyPet-x86_64"
  lipo -create "$FIX/HappyPet-arm64" "$FIX/HappyPet-x86_64" -output "$BIN"
  lipo -info "$BIN"
else
  echo "🔨 编译中 (${ARCH})..."
  compile_arch "$ARCH" "$BIN"
fi

# 本地临时签名,避免首次运行被拦
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ 构建完成: $APP"
echo "   运行: open \"$APP\"   或   ./run.sh"