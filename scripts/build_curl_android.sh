#!/bin/bash
# Simple curl build for Android
# Usage: ./build_curl.sh /path/to/ndk
set -e

NDK="$1"
[ -z "$NDK" ] && echo "Usage: $0 /path/to/ndk" && exit 1

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
API=24
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc)

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
ROOT="$SCRIPTS/build_curl_simple"
OUTDIR="$SCRIPTS/../android/app/src/main/jniLibs"
mkdir -p "$ROOT"
cd "$ROOT"

echo "=== Downloading sources ==="
[ -f curl-8.13.0.tar.xz ] || curl -LO https://curl.se/download/curl-8.13.0.tar.xz
[ -d curl-8.13.0 ] || tar xf curl-8.13.0.tar.xz
[ -f openssl-3.5.0.tar.gz ] || curl -LO https://www.openssl.org/source/openssl-3.5.0.tar.gz
[ -d openssl-3.5.0 ] || tar xf openssl-3.5.0.tar.gz

ARCHS="arm64-v8a:aarch64-linux-android:android-arm64 armeabi-v7a:armv7a-linux-androideabi:android-arm x86_64:x86_64-linux-android:android-x86_64"

for ARCH_PAIR in $ARCHS; do
    IFS=":" read -r ABI TARGET SSL_TARGET <<< "$ARCH_PAIR"
    echo ""
    echo "=== Building $ABI ==="
    
    PREFIX="$ROOT/out/$ABI"
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"
    
    CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
    CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
    AR="$TOOLCHAIN/bin/llvm-ar"
    STRIP="$TOOLCHAIN/bin/llvm-strip"
    export ANDROID_NDK_ROOT="$NDK"
    export PATH="$TOOLCHAIN/bin:$PATH"
    
    # OpenSSL
    echo "  OpenSSL..."
    cd "$ROOT/openssl-3.5.0"
    make clean 2>/dev/null || true
    ./Configure "$SSL_TARGET" -D__ANDROID_API__=$API --prefix="$PREFIX" no-shared no-tests
    make -j$JOBS && make install_sw
    make clean 2>/dev/null || true
    
    # curl
    echo "  curl..."
    cd "$ROOT/curl-8.13.0"
    make clean 2>/dev/null || true
    autoreconf -fi 2>/dev/null || true
    CC="$CC" CXX="$CXX" AR="$AR" \
    ./configure \
        --host="$TARGET" \
        --prefix="$PREFIX" \
        --with-openssl="$PREFIX" \
        --with-zlib \
        --without-libpsl \
        --enable-shared --disable-static \
        --disable-ldap --disable-manual \
        CFLAGS="-O3" \
        LDFLAGS="-L$PREFIX/lib" \
        LIBS="-lssl -lcrypto"
    CC="$CC" make -j$JOBS && make install
    
    # Copy
    DEST="$OUTDIR/$ABI"
    mkdir -p "$DEST"
    cp "$PREFIX/lib/libcurl.so" "$DEST/" 2>/dev/null || true
    "$STRIP" "$DEST/libcurl.so" 2>/dev/null || true
    echo "  Done: $DEST/libcurl.so ($(ls -lh "$DEST/libcurl.so" 2>/dev/null | awk '{print $5}'))"
done

echo ""
echo "=== Complete ==="
ls -lh $OUTDIR/*/libcurl.so
