#!/bin/bash
# Builds OpenSSL and Hunspell for macOS, universal (arm64 from 11.0, x86_64
# from 10.15), with @rpath install names, ad-hoc signed.
# Usage: scripts/mac-build.sh <openssl version> <out folder> [work folder]
set -euo pipefail
V=$1; OUT=$2; W=${3:-$PWD/work}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$W" "$OUT"; OUT=$(cd "$OUT" && pwd); W=$(cd "$W" && pwd)
J=$(sysctl -n hw.ncpu)

fetch() { # url file sha
  [ -f "$2" ] || curl -fsSL --retry 3 -o "$2" "$1"
  echo "$3  $2" | shasum -a 256 -c -
}

if [[ $V == 1.* ]]; then TAG=OpenSSL_${V//./_}; else TAG=openssl-$V; fi
OSSL=$W/openssl-$V.tar.gz
URL=https://github.com/openssl/openssl/releases/download/$TAG/openssl-$V.tar.gz
if [ "$V" = 1.1.1w ]; then SHA=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
else curl -fsSL --retry 3 -o "$OSSL.sha256" "$URL.sha256"; SHA=$(awk '{print $1; exit}' "$OSSL.sha256"); fi
fetch "$URL" "$OSSL" "$SHA"
HS=$W/hunspell-1.7.2.tar.gz
fetch https://github.com/hunspell/hunspell/releases/download/v1.7.2/hunspell-1.7.2.tar.gz "$HS" \
  11ddfa39afe28c28539fe65fc4f1592d410c1e9b6dd7d8a91ca25d85e9ec65b8
rm -rf "$W/src"; mkdir -p "$W/src"
tar -xzf "$OSSL" -C "$W/src"; tar -xzf "$HS" -C "$W/src"

SSLMAJ=$([[ $V == 1.* ]] && echo 1.1 || echo 3)
for A in arm64 x86_64; do
  MIN=$([ $A = arm64 ] && echo 11.0 || echo 10.15)
  B=$W/build/$A; rm -rf "$B"; mkdir -p "$B"
  # OpenSSL (Configure takes the target, so x86_64 is built on arm64 too)
  cp -Rp "$W/src/openssl-$V" "$B/openssl"
  (cd "$B/openssl" && CC=clang ./Configure darwin64-$A-cc shared no-tests \
     --prefix="$B/inst" --openssldir=/usr/local/etc/openssl@$SSLMAJ \
     -mmacosx-version-min=$MIN -headerpad_max_install_names && make -j$J build_libs >/dev/null)
  cp "$B/openssl/libssl.$SSLMAJ.dylib" "$B/openssl/libcrypto.$SSLMAJ.dylib" "$B/"
  # Hunspell, as Tero loads it
  clang++ -arch $A -mmacosx-version-min=$MIN -O2 -std=c++11 -dynamiclib -fvisibility=hidden \
    -DBUILDING_LIBHUNSPELL -headerpad_max_install_names -install_name @rpath/libhunspellx64.dylib \
    "$W/src/hunspell-1.7.2/src/hunspell/"*.cxx -o "$B/libhunspellx64.dylib"
done

for n in libssl.$SSLMAJ.dylib libcrypto.$SSLMAJ.dylib libhunspellx64.dylib; do
  lipo -create "$W/build/arm64/$n" "$W/build/x86_64/$n" -output "$OUT/$n"
  chmod u+w "$OUT/$n"
  install_name_tool -id @rpath/$n "$OUT/$n" 2>/dev/null
done
for dep in $(otool -L "$OUT/libssl.$SSLMAJ.dylib" | awk '/libcrypto/{print $1}'); do
  install_name_tool -change "$dep" @loader_path/libcrypto.$SSLMAJ.dylib "$OUT/libssl.$SSLMAJ.dylib" 2>/dev/null
done
codesign -f -s - "$OUT"/*.dylib
cp "$(ls -d "$W/src/openssl-$V"/LICENSE* | head -1)" "$OUT/LICENSE-OpenSSL.txt"
cp "$W/src/hunspell-1.7.2/COPYING.MPL" "$OUT/LICENSE-Hunspell-MPL.txt"

# checks: both archs, minimum macOS, only system dependencies besides ours
bad=0
for f in "$OUT"/*.dylib; do
  n=$(basename "$f")
  a=$(otool -arch arm64 -l "$f" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2;exit}')
  x=$(otool -arch x86_64 -l "$f" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2;exit} /LC_VERSION_MIN_MACOSX/{g=1} g&&/ version/{print $2;exit}')
  echo "$n arm64=$a x86_64=$x archs=$(lipo -archs "$f")"
  [ "$a" = 11.0 ] || { echo "  BAD arm64 minimum"; bad=1; }
  [ "$x" = 10.15 ] || { echo "  BAD x86_64 minimum"; bad=1; }
  for A in arm64 x86_64; do
    for d in $(otool -arch $A -L "$f" | tail -n +2 | awk '{print $1}'); do
      case $d in
        /usr/lib/*|/System/*) ;;
        @rpath/*|@loader_path/*) [ -f "$OUT/$(basename $d)" ] || { echo "  BAD missing $d"; bad=1; } ;;
        *) echo "  BAD dependency $d"; bad=1 ;;
      esac
    done
  done
  codesign -v "$f" || { echo "  BAD signature"; bad=1; }
done
if otool -L "$OUT"/*.dylib | grep -v ":$" | grep -q "$W"; then echo "BAD build paths"; bad=1; fi

clang -arch arm64 -arch x86_64 -mmacosx-version-min=10.15 -o "$W/libtest" "$ROOT/tests/libtest.c"
exit $bad
