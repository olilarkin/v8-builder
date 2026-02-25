#!/bin/sh
set -e

lib_path="$1"

if [ -z "$lib_path" ]; then
  echo "Usage: $0 <path-to-libv8_monolith.a>"
  exit 1
fi

if [ ! -f "$lib_path" ]; then
  echo "Error: $lib_path not found"
  exit 1
fi

platform="$(uname -s)"

# Detect LLVM tools — V8 is built with Clang/LLD, so we must use LLVM tools
# Try exact name, then versioned names (e.g. ld.lld-18), then V8's bundled copy
detect_tool() {
  tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "$tool"
    return
  fi
  # Try versioned names (llvm packages on Ubuntu install as e.g. ld.lld-18)
  for candidate in $(compgen -c "$tool-" 2>/dev/null | sort -t- -k2 -n -r); do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return
    fi
  done
  # Try xcrun on macOS
  if command -v xcrun >/dev/null 2>&1 && xcrun -f "$tool" >/dev/null 2>&1; then
    echo "xcrun $tool"
    return
  fi
  echo ""
}

# V8's bundled LLVM toolchain
v8_llvm_bin="$(cd "$(dirname "$0")" && pwd)/v8/third_party/llvm-build/Release+Asserts/bin"

find_tool() {
  tool="$1"
  # Check V8's bundled LLVM first
  if [ -x "$v8_llvm_bin/$tool" ]; then
    echo "$v8_llvm_bin/$tool"
  else
    detect_tool "$tool"
  fi
}

LLD=$(find_tool ld.lld)
OBJCOPY=$(find_tool llvm-objcopy)
AR=$(find_tool llvm-ar)
NM=$(find_tool llvm-nm)

if [ -z "$OBJCOPY" ]; then
  echo "Error: llvm-objcopy not found"
  exit 1
fi

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

echo "Deconflicting $lib_path..."

# Step 1: Partial link all .o files into a single relocatable object
case "$platform" in
  Linux)
    if [ -z "$LLD" ]; then
      echo "Error: ld.lld not found (required for V8 objects built with Clang)"
      exit 1
    fi
    $LLD -r -o "$tmpdir/v8_combined.o" --whole-archive "$lib_path"
    ;;
  Darwin)
    darwin_arch=""
    case "${RUNNER_ARCH:-$(uname -m)}" in
      ARM64|arm64|aarch64)
        darwin_arch="arm64"
        ;;
      X64|x64|x86_64|amd64)
        darwin_arch="x86_64"
        ;;
      *)
        echo "Unsupported macOS arch: ${RUNNER_ARCH:-$(uname -m)}"
        exit 1
        ;;
    esac
    # On modern Xcode, calling ld directly requires explicit -platform_version.
    # Use the compiler driver so platform metadata is provided automatically.
    if command -v xcrun >/dev/null 2>&1 && xcrun -f clang++ >/dev/null 2>&1; then
      xcrun clang++ -nostdlib -arch "$darwin_arch" -r -o "$tmpdir/v8_combined.o" -Wl,-all_load "$lib_path"
    elif command -v clang++ >/dev/null 2>&1; then
      clang++ -nostdlib -arch "$darwin_arch" -r -o "$tmpdir/v8_combined.o" -Wl,-all_load "$lib_path"
    else
      echo "Error: clang++ not found (required for macOS deconflict link)"
      exit 1
    fi
    ;;
  *)
    echo "Unsupported platform: $platform"
    exit 1
    ;;
esac

# Step 2: Localize abseil and zlib symbols so they don't conflict with Skia/Dawn
$OBJCOPY --regex \
  --localize-symbol='.*absl.*' \
  --localize-symbol='^(deflate|inflate|compress|uncompress|adler32|crc32|gz|zlib|zError|get_crc_table|cpu_check_features).*' \
  "$tmpdir/v8_combined.o"

# Step 3: Re-create the static archive
case "$platform" in
  Linux)
    ${AR:-ar} rcs "$lib_path" "$tmpdir/v8_combined.o"
    ;;
  Darwin)
    libtool -static -o "$lib_path" "$tmpdir/v8_combined.o"
    ;;
esac

# Verify no global abseil/zlib symbols remain
echo "Verifying no global abseil/zlib symbols..."
_nm="${NM:-nm}"
if $_nm -g "$lib_path" | grep -iE '(absl|deflate|inflate|adler32|crc32)' >/dev/null 2>&1; then
  echo "WARNING: conflicting symbols still present"
  $_nm -g "$lib_path" | grep -iE '(absl|deflate|inflate|adler32|crc32)' | head -20
else
  echo "OK: no conflicting global symbols"
fi

echo "Deconflicted: $lib_path"
