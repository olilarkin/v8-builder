#!/bin/sh

set -e

dir="$(cd "$(dirname "$0")" && pwd)"
os="$(sh "${dir}/scripts/get_os.sh")"

if [ ! -d "${dir}/v8" ]; then
  echo "v8 not found"
  exit 1
fi

# Use V8's bundled Clang and lld since V8 is built with is_clang=true, use_lld=true
v8_clang="${dir}/v8/third_party/llvm-build/Release+Asserts/bin/clang++"
linker_flags=""
test_cflags=""
extra_libs="-ldl"

if [ -x "$v8_clang" ]; then
  CXX="$v8_clang"
  # lld on macOS is brittle with Apple SDK/system libraries in this sample link.
  if [ "$os" != "macOS" ]; then
    linker_flags="-fuse-ld=lld"
  fi
  echo "Using V8's bundled Clang: $CXX"
else
  CXX="g++"
  echo "Warning: V8 Clang not found, falling back to system g++"
fi

if [ "$os" = "macOS" ]; then
  sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  if [ -n "$sdk_path" ]; then
    test_cflags="-isysroot $sdk_path"
    linker_flags="$linker_flags -Wl,-syslibroot,$sdk_path"
  fi
  extra_libs=""
fi

(
  set -x
  $CXX -I"${dir}/v8" -I"${dir}/v8/include" \
    "${dir}/v8/samples/hello-world.cc" -o hello_world \
    -lv8_monolith -L"${dir}/v8/out/release/obj/" \
    -pthread -std=c++20 $test_cflags $extra_libs $linker_flags
)

sh -c "./hello_world"
