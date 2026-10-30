#!/usr/bin/env bash
# 打包一份可以直接发给对方的礼物包
#
# 只编 universal 二进制 + adhoc 签名,不装、不自启,解压放哪都能双击开。
#
# 关于「Apple 无法验证…」:没有付费开发者证书的 app 过不了 Gatekeeper 公证,
# 但我们的签名是完整有效的(codesign valid + 满足 DR),所以系统提示是
# 「无法验证」而不是「已损坏」——这种情况能在「系统设置 › 隐私与安全性」
# 里永久放行一次就好。另外:用 U 盘拷过去的文件根本不带隔离标记,
# 连放行都不用,这是最省事的送法。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
PKG="$DIST/HappyPet"

echo "① 编译 universal 版本(arm64 + x86_64,任何 Mac 都能开)"
UNIVERSAL=1 "$ROOT/build.sh"

echo "② 组装礼物包"
mkdir -p "$PKG"
ditto "$ROOT/build/HappyPet.app" "$PKG/HappyPet.app"

echo "③ 自检签名(必须 valid,否则对方会看到「已损坏」而无法放行)"
codesign -v "$PKG/HappyPet.app" && echo "   ✅ 签名有效"

echo "④ 压缩"
cd "$DIST"
ditto -c -k --sequesterRsrc --keepParent HappyPet HappyPet.zip

cat <<'TIPS'

✅ 礼物包好了: dist/HappyPet.zip

━━ 送法 A:U 盘(最省事,推荐)━━
  把 HappyPet.app 拷到 U 盘,再从 U 盘拷到她电脑。
  从外部磁盘拷来的文件不带隔离标记,双击直接开,什么都不用点。

━━ 送法 B:微信 / 网盘 / AirDrop ━━
  传输会打上隔离标记,她第一次打开要放行一次:
  1. 解压,把 HappyPet.app 拖到「应用程序」或桌面
  2. 双击 → 弹出「Apple 无法验证…」→ 点「完成」(别点移到废纸篓)
  3. 打开「系统设置」→「隐私与安全性」→ 往下滑到底
     会看到一行「已阻止使用 HappyPet…」→ 点右边的「仍要打开」
  4. 再双击 HappyPet,这次会问「确定要打开吗」→ 点「打开」
  之后就正常了,放行只需一次。

TIPS