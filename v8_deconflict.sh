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

# Detect tools
if command -v llvm-objcopy >/dev/null 2>&1; then
  OBJCOPY=llvm-objcopy
elif command -v xcrun >/dev/null 2>&1 && xcrun -f llvm-objcopy >/dev/null 2>&1; then
  OBJCOPY="xcrun llvm-objcopy"
else
  echo "Error: llvm-objcopy not found"
  exit 1
fi

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

echo "Deconflicting $lib_path..."

# Step 1: Partial link all .o files into a single relocatable object
case "$platform" in
  Linux)
    ld -r -o "$tmpdir/v8_combined.o" --whole-archive "$lib_path"
    ;;
  Darwin)
    ld -r -o "$tmpdir/v8_combined.o" -all_load "$lib_path"
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
    ar rcs "$lib_path" "$tmpdir/v8_combined.o"
    ;;
  Darwin)
    libtool -static -o "$lib_path" "$tmpdir/v8_combined.o"
    ;;
esac

# Verify no global abseil/zlib symbols remain
echo "Verifying no global abseil/zlib symbols..."
if nm -g "$lib_path" | grep -iE '(absl|deflate|inflate|adler32|crc32)' >/dev/null 2>&1; then
  echo "WARNING: conflicting symbols still present"
  nm -g "$lib_path" | grep -iE '(absl|deflate|inflate|adler32|crc32)' | head -20
else
  echo "OK: no conflicting global symbols"
fi

echo "Deconflicted: $lib_path"
