#!/bin/bash

# The following variables influence the operation of this build script:
# -f: Soft clean, ensuring re-build of oqs-provider binary
# -F: Hard clean, wiping oqs-provider, OpenSSL & liboqs dirs
# EnvVars:
#   CMAKE_PARAMS         passed through to all cmake invocations
#   MAKE_PARAMS          passed to make/ninja (e.g., "-j")
#   OQSPROV_CMAKE_PARAMS passed to the oqs-provider cmake run
#   LIBOQS_BRANCH        branch of liboqs to checkout (default "main")
#   OQS_ALGS_ENABLED     limit which PQ algs to build (e.g. "STD")
#   OQS_LIBJADE_BUILD    ON/OFF libjade support (default OFF)
#   OPENSSL_INSTALL      path to an existing OpenSSL3 install (skips build)
#   OPENSSL_BRANCH       branch of OpenSSL to build if OPENSSL_INSTALL unset
#   OSSL_CONFIG          extra flags to pass to OpenSSL’s ./config
#   liboqs_DIR           path to an installed liboqs

set -euo pipefail

if [[ "$OSTYPE" == "darwin"* ]]; then
   SHLIBEXT="dylib"; STATLIBEXT="dylib"
else
   SHLIBEXT="so";   STATLIBEXT="a"
fi

if [ $# -gt 0 ]; then
  [[ "$1" == "-f" ]] && rm -rf _build
  [[ "$1" == "-F" ]] && rm -rf _build openssl liboqs .local
fi

: "${LIBOQS_BRANCH:=main}"
: "${OQS_ALGS_ENABLED:=}"
: "${OQS_LIBJADE_BUILD:=OFF}"

DOQS_ALGS_ENABLED=${OQS_ALGS_ENABLED:+-DOQS_ALGS_ENABLED=$OQS_ALGS_ENABLED}
DOQS_LIBJADE_BUILD=-DOQS_LIBJADE_BUILD=$OQS_LIBJADE_BUILD

# ---------------------------------------------------------------------------
# Helper: detect a system-installed OpenSSL3 (e.g. /usr/local/ssl)
# ---------------------------------------------------------------------------
detect_system_ossl() {
  local dir
  dir=$(openssl version -d 2>/dev/null | cut -d\" -f2 || :)
  if [[ -n "$dir" ]]; then
    for sub in lib lib64; do
      if [[ -f "$dir/$sub/libcrypto.so.3" ]]; then
        echo "$dir"
        return
      fi
    done
  fi
}

# ---------------------------------------------------------------------------
# Decide which OpenSSL to use
# ---------------------------------------------------------------------------
if [ -z "${OPENSSL_INSTALL:-}" ]; then
  # 1) Try system OpenSSL3
  OPENSSL_INSTALL=$(detect_system_ossl || :)

  # 2) If none, or a specific branch requested, build from source
  if [ -z "$OPENSSL_INSTALL" ] || [ -n "${OPENSSL_BRANCH:-}" ]; then
    : "${OPENSSL_BRANCH:=master}"
    echo "→ Building OpenSSL3 from branch $OPENSSL_BRANCH …"

    if [ ! -d openssl ]; then
      OSSL_PREFIX="$(pwd)/.local"
      git clone --depth 1 --branch "$OPENSSL_BRANCH" \
        https://github.com/openssl/openssl.git openssl

      cd openssl
      LDFLAGS="-Wl,-rpath -Wl,${OSSL_PREFIX}/lib64" \
        ./config $OSSL_CONFIG --prefix="$OSSL_PREFIX"
      make $MAKE_PARAMS
      make install_sw install_ssldirs
      cd ..

      # some CMake versions expect a plain "lib" directory
      cd "$OSSL_PREFIX"
      [[ -d lib64 && ! -e lib ]] && ln -s lib64 lib
      cd -
    fi

    OPENSSL_INSTALL=${OPENSSL_INSTALL:-$OSSL_PREFIX}
  fi
fi

# Tell pkg-config / CMake / loader where to find this OpenSSL
export PKG_CONFIG_PATH="$OPENSSL_INSTALL/lib64/pkgconfig:$OPENSSL_INSTALL/lib/pkgconfig:$PKG_CONFIG_PATH"
export CMAKE_PREFIX_PATH="$OPENSSL_INSTALL:$CMAKE_PREFIX_PATH"
export LD_LIBRARY_PATH="$OPENSSL_INSTALL/lib64:$OPENSSL_INSTALL/lib:$LD_LIBRARY_PATH"

# ---------------------------------------------------------------------------
# Build (or reuse) liboqs
# ---------------------------------------------------------------------------
if [ -z "${liboqs_DIR:-}" ]; then
  if [ ! -f ".local/lib/liboqs.$STATLIBEXT" ]; then
    echo "→ Building liboqs (branch $LIBOQS_BRANCH)…"

    git clone --depth 1 --branch "$LIBOQS_BRANCH" https://github.com/open-quantum-safe/liboqs.git liboqs

    if [ "$LIBOQS_BRANCH" != "main" ] && [ -f oqs-template/generate.yml-$LIBOQS_BRANCH ]; then
      pip install -r oqs-template/requirements.txt
      cp oqs-template/generate.yml-$LIBOQS_BRANCH oqs-template/generate.yml
      LIBOQS_SRC_DIR="$(pwd)/liboqs" \
        python3 oqs-template/generate.py
    fi

    cd liboqs
    cmake -GNinja \
      $CMAKE_PARAMS $DOQS_ALGS_ENABLED \
      -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" \
      $DOQS_LIBJADE_BUILD \
      -DCMAKE_INSTALL_PREFIX="$(pwd)/../.local" \
      -S . -B _build
    cd _build && ninja && ninja install
    cd ../..
  fi
  export liboqs_DIR="$(pwd)/.local"
fi

# ---------------------------------------------------------------------------
# Build the OQS-OpenSSL provider
# ---------------------------------------------------------------------------
if [ ! -f "_build/lib/oqsprovider.$SHLIBEXT" ]; then
  echo "→ Building oqs-provider…"
  BUILD_TYPE=""
  cd _build 2>/dev/null || cmake $CMAKE_PARAMS \
    -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    $OQSPROV_CMAKE_PARAMS \
    -S . -B _build

  cmake --build _build
fi

echo "✅ Done. provider at: $OPENSSL_INSTALL/lib64/ossl-modules/oqsprovider.so"
