#!/bin/sh
# Builds mbedTLS for the app (armv7, iOS 5.0 so one build runs on iOS 5 and 6) from the verified release tarball into out/ios.
# Same scripts and configuration as IG6.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
VER=3.6.7
"$HERE/fetch.sh" --verify-only
TARBALL="$HERE/download/mbedtls-$VER.tar.bz2"
SDK_IOS="${THEOS:-$HOME/theos}/sdks/iPhoneOS9.3.sdk"
WARN="-Werror=unguarded-availability -Werror=partial-availability -Wno-deprecated-module-dot-map"

build() { # $1 variant, $2 clang target, $3 sysroot
  WORK="$HERE/build/$1"
  SRC="$WORK/mbedtls-$VER"
  rm -rf "$WORK" && mkdir -p "$WORK"
  tar -xjf "$TARBALL" -C "$WORK"
  CFLAGS="-target $2 -isysroot $3 -marm -Os -I$SRC/include -I$HERE -include $HERE/mbedtls_ios6_predef.h $WARN"
  make -C "$SRC/library" -j8 CC="xcrun clang" AR="xcrun ar" CFLAGS="$CFLAGS" libmbedcrypto.a libmbedx509.a libmbedtls.a >/dev/null
  xcrun clang $CFLAGS -c "$HERE/mbedtls_ios6_alt.c" -o "$WORK/mbedtls_ios6_alt.o"
  OUT="$HERE/out/$1"
  rm -rf "$OUT" && mkdir -p "$OUT/lib"
  cp "$SRC/library/libmbedtls.a" "$SRC/library/libmbedx509.a" "$SRC/library/libmbedcrypto.a" "$OUT/lib/"
  xcrun ar rcs "$OUT/lib/libmbedcrypto.a" "$WORK/mbedtls_ios6_alt.o"
  cp -R "$SRC/include" "$OUT/include"
  cp "$HERE/mbedtls_ios6_config.h" "$HERE/mbedtls_ios6_predef.h" "$OUT/include/"
}

build ios armv7-apple-ios5.0 "$SDK_IOS"
echo "built $HERE/out/ios"
