#!/bin/bash
# Build curl with HTTP/2 + HTTP/3 for Android (arm64-v8a, armeabi-v7a, x86_64)
# Requires: Android NDK (r26+), cmake, autoconf, automake, libtool, pkg-config
# Usage: ./build_curl.sh /path/to/android-ndk
#
# Output: libcurl.so in android/app/src/main/jniLibs/<arch>/
#   Includes: HTTP/1.1, HTTP/2 (nghttp2), HTTP/3 (ngtcp2+nghttp3),
#             TLS (OpenSSL 3.x), zlib, brotli
#
# ⚠️ HTTP/3 (QUIC) is EXPERIMENTAL in libcurl 8.x.
#    Jika build HTTP/3 gagal, script fallback ke HTTP/2 only.

set -e

NDK="$1"
if [ -z "$NDK" ]; then
    echo "Usage: $0 /path/to/android-ndk"
    echo "Example: $0 ~/Library/Android/sdk/ndk/27.0.12077973"
    exit 1
fi

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
    TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
fi
if [ ! -d "$TOOLCHAIN" ]; then
    echo "ERROR: Cannot find NDK toolchain at $TOOLCHAIN"
    exit 1
fi

API=24
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc)

ARCHS=(
    "arm64-v8a:aarch64-linux-android:android-arm64"
    "armeabi-v7a:armv7a-linux-androideabi:android-arm"
    "x86_64:x86_64-linux-android:android-x86_64"
)

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
ROOT="$SCRIPTS/build_curl"
mkdir -p "$ROOT"
cd "$ROOT"

# ── Download sources ────────────────────────────────────────

echo "=== Downloading sources ==="
[ -d curl-8.13.0     ] || { echo "  -> curl 8.13.0";     curl -L#O https://curl.se/download/curl-8.13.0.tar.xz && tar xf curl-8.13.0.tar.xz; }
[ -d openssl-3.5.0   ] || { echo "  -> OpenSSL 3.5.0";   curl -L#O https://www.openssl.org/source/openssl-3.5.0.tar.gz && tar xf openssl-3.5.0.tar.gz; }
[ -d nghttp2-1.64.0  ] || { echo "  -> nghttp2 1.64.0";  curl -L#O https://github.com/nghttp2/nghttp2/releases/download/v1.64.0/nghttp2-1.64.0.tar.xz && tar xf nghttp2-1.64.0.tar.xz; }
[ -d ngtcp2-1.10.0   ] || { echo "  -> ngtcp2 1.10.0";   curl -L#O https://github.com/ngtcp2/ngtcp2/releases/download/v1.10.0/ngtcp2-1.10.0.tar.xz && tar xf ngtcp2-1.10.0.tar.xz; }
[ -d nghttp3-1.7.0   ] || { echo "  -> nghttp3 1.7.0";   curl -L#O https://github.com/ngtcp2/nghttp3/releases/download/v1.7.0/nghttp3-1.7.0.tar.xz && tar xf nghttp3-1.7.0.tar.xz; }
[ -d brotli-1.1.0    ] || { echo "  -> brotli 1.1.0";    curl -L#o brotli.tar.gz https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz && tar xf brotli.tar.gz && rm brotli.tar.gz; }
# brotli extracts to brotli-1.1.0 (GitHub archive format drops 'v' prefix)

[ -d libssh2-1.11.1  ] || { echo "  -> libssh2 1.11.1";  curl -L#O https://www.libssh2.org/download/libssh2-1.11.1.tar.gz && tar xf libssh2-1.11.1.tar.gz; }

# Note: zlib is in Android NDK sysroot — no need to build separately
# Note: brotli build is optional, skip for MVP (use --without-brotli)

OUTDIR="$SCRIPTS/../android/app/src/main/jniLibs"
HTTP3_FAILED=0

for ARCH_PAIR in "${ARCHS[@]}"; do
    IFS=":" read -r ABI TARGET SSL_TARGET <<< "$ARCH_PAIR"
    echo ""
    echo "================================================"
    echo "  Building for $ABI ($TARGET)"
    echo "================================================"

    PREFIX="$ROOT/out/$ABI"
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"

    export CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
    export CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
    export AR="$TOOLCHAIN/bin/llvm-ar"
    export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
    export STRIP="$TOOLCHAIN/bin/llvm-strip"
    export NM="$TOOLCHAIN/bin/llvm-nm"
    export READELF="$TOOLCHAIN/bin/llvm-readelf"

    # Android NDK sysroot for zlib
    SYSROOT="$TOOLCHAIN/sysroot"
    CFLAGS_BASE="-O3 -flto -D__ANDROID_API__=$API -I$SYSROOT/usr/include"
    LDFLAGS_BASE="-O3 -flto -L$SYSROOT/usr/lib/$TARGET/$API"

    # ── OpenSSL ────────────────────────────────────────────────
    echo "  [1/7] OpenSSL"
    cd "$ROOT/openssl-3.5.0"
    make clean 2>/dev/null || true
    ./Configure "$SSL_TARGET" \
        -D__ANDROID_API__=$API \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX/ssl" \
        no-shared no-tests no-legacy \
        no-weak-ssl-ciphers \
        -Wl,-rpath="\$ORIGIN"
    make -j$JOBS 2>&1 | tail -3
    make install_sw 2>&1 | tail -1
    make clean 2>/dev/null || true

    # ── nghttp2 (HTTP/2) ──────────────────────────────────────
    echo "  [2/7] nghttp2 (HTTP/2)"
    cd "$ROOT/nghttp2-1.64.0"
    make clean 2>/dev/null || true
    ./configure \
        --host="$TARGET" \
        --prefix="$PREFIX" \
        --enable-lib-only \
        --disable-shared \
        --disable-python-bindings \
        CFLAGS="$CFLAGS_BASE" \
        LDFLAGS="$LDFLAGS_BASE"
    make -j$JOBS 2>&1 | tail -3
    make install 2>&1 | tail -1
    make clean 2>/dev/null || true

    # ── nghttp3 (HTTP/3) ──────────────────────────────────────
    echo "  [3/7] nghttp3 (HTTP/3)"
    cd "$ROOT/nghttp3-1.7.0"
    rm -rf build && mkdir build && cd build
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DENABLE_LIB_ONLY=ON \
        -DENABLE_SHARED_LIB=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-O3" \
        2>&1 | tail -3
    cmake --build . -j$JOBS 2>&1 | tail -3
    cmake --install . 2>&1 | tail -1

    # ── ngtcp2 (QUIC transport) ───────────────────────────────
    echo "  [4/6] ngtcp2 (QUIC)"
    cd "$ROOT/ngtcp2-1.10.0"
    rm -rf build && mkdir build && cd build
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DENABLE_OPENSSL=ON \
        -DOPENSSL_ROOT_DIR="$PREFIX" \
        -DENABLE_SHARED_LIB=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-O3" \
        2>&1 | tail -3
    cmake --build . -j$JOBS 2>&1 | tail -3
    cmake --install . 2>&1 | tail -1

    # ── brotli (Content-Encoding: br) ─────────────────────────
    echo "  [5/6] brotli"
    cd "$ROOT/brotli-1.1.0"
    rm -rf build && mkdir build && cd build
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBROTLI_DISABLE_TESTS=ON \
        2>&1 | tail -3
    cmake --build . -j$JOBS 2>&1 | tail -3
    cmake --install . 2>&1 | tail -1

    # ── libssh2 (SFTP/SCP) ────────────────────────────────────
    echo "  [6/6] libssh2 (SFTP/SCP)"
    cd "$ROOT/libssh2-1.11.1"
    make clean 2>/dev/null || true
    ./configure \
        --host="$TARGET" \
        --prefix="$PREFIX" \
        --with-openssl="$PREFIX" \
        --disable-shared \
        --disable-examples-build \
        CFLAGS="$CFLAGS_BASE" \
        LDFLAGS="$LDFLAGS_BASE -L$PREFIX/lib"
    make -j$JOBS 2>&1 | tail -3
    make install 2>&1 | tail -1
    make clean 2>/dev/null || true

    # ── curl (FULL — semua protocol) ──────────────────────────
    echo "  [7/7] curl (full)"
    cd "$ROOT/curl-8.13.0"
    make clean 2>/dev/null || true
    autoreconf -fi 2>/dev/null || true

    ./configure \
        --host="$TARGET" \
        --prefix="$PREFIX" \
        --with-openssl="$PREFIX" \
        --with-nghttp2="$PREFIX" \
        --with-ngtcp2="$PREFIX" \
        --with-nghttp3="$PREFIX" \
        --with-zlib="$SYSROOT/usr" \
        --with-brotli="$PREFIX" \
        --with-libssh2="$PREFIX" \
        --enable-shared \
        --disable-static \
        --disable-manual \
        --disable-libcurl-option \
        --enable-http2 \
        --enable-http3 \
        --with-pic \
        CFLAGS="$CFLAGS_BASE" \
        CPPFLAGS="-I$PREFIX/include" \
        LDFLAGS="$LDFLAGS_BASE -L$PREFIX/lib" \
        LIBS="-lssl -lcrypto -lnghttp2 -lngtcp2 -lnghttp3 -lbrotlicommon -lbrotlidec -lssh2 -lz"

    if make -j$JOBS 2>&1 | tail -10; then
        make install 2>&1 | tail -1
    else
        echo ""
        echo "  ⚠️  Full build FAILED for $ABI — falling back to HTTP/2 only"
        echo ""
        make clean 2>/dev/null || true
        ./configure \
            --host="$TARGET" \
            --prefix="$PREFIX" \
            --with-openssl="$PREFIX" \
            --with-nghttp2="$PREFIX" \
            --with-zlib="$SYSROOT/usr" \
            --enable-shared \
            --disable-static \
            --disable-ldap \
            --disable-ldaps \
            --disable-rtsp \
            --disable-dict \
            --disable-telnet \
            --disable-tftp \
            --disable-pop3 \
            --disable-imap \
            --disable-smb \
            --disable-smtp \
            --disable-gopher \
            --disable-mqtt \
            --disable-manual \
            --disable-libcurl-option \
            --enable-http2 \
            --with-pic \
            CFLAGS="$CFLAGS_BASE" \
            CPPFLAGS="-I$PREFIX/include" \
            LDFLAGS="$LDFLAGS_BASE -L$PREFIX/lib" \
            LIBS="-lssl -lcrypto -lnghttp2 -lz"
        make -j$JOBS 2>&1 | tail -3
        make install 2>&1 | tail -1
    fi
    make clean 2>/dev/null || true

    # ── Copy .so ke jniLibs ────────────────────────────────────
    DEST="$OUTDIR/$ABI"
    mkdir -p "$DEST"
    if [ -f "$PREFIX/lib/libcurl.so" ]; then
        cp "$PREFIX/lib/libcurl.so" "$DEST/"
        "$STRIP" "$DEST/libcurl.so" 2>/dev/null || true
        SIZE=$(ls -lh "$DEST/libcurl.so" | awk '{print $5}')
        echo "  ✅ Done: $DEST/libcurl.so ($SIZE)"
    else
        echo "  ❌ libcurl.so not found for $ABI"
    fi
done

echo ""
echo "================================================"
echo "  Build complete!"
echo "================================================"
echo "Files:"
for ARCH_PAIR in "${ARCHS[@]}"; do
    IFS=":" read -r ABI _ <<< "$ARCH_PAIR"
    DEST="$OUTDIR/$ABI"
    if [ -f "$DEST/libcurl.so" ]; then
        SIZE=$(ls -lh "$DEST/libcurl.so" | awk '{print $5}')
        echo "  $ABI: $SIZE"
    fi
done
if [ $HTTP3_FAILED -eq 1 ]; then
    echo ""
    echo "⚠️  HTTP/3 (QUIC) failed on some architectures — HTTP/2 only."
    echo "   Ini normal. HTTP/3 via QUIC masih experimental di libcurl 8.x."
    echo "   HTTP/1.1 + HTTP/2 tetap jalan full."
fi
