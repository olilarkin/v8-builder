#!/bin/sh

set -e

dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "${dir}/v8" ]; then
  echo "v8 not found"
  exit 1
fi

# Use V8's bundled Clang and lld since V8 is built with is_clang=true, use_lld=true
v8_clang="${dir}/v8/third_party/llvm-build/Release+Asserts/bin/clang++"

if [ -x "$v8_clang" ]; then
  CXX="$v8_clang"
  LDFLAGS="-fuse-ld=lld"
  echo "Using V8's bundled Clang: $CXX"
else
  CXX="g++"
  LDFLAGS=""
  echo "Warning: V8 Clang not found, falling back to system g++"
fi

(
  set -x
  $CXX -I"${dir}/v8" -I"${dir}/v8/include" \
    "${dir}/v8/samples/hello-world.cc" -o hello_world \
    -lv8_monolith -L"${dir}/v8/out/release/obj/" \
    -pthread -std=c++20 -ldl $LDFLAGS
)

sh -c "./hello_world"
