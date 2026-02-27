#!/bin/sh

set -e

dir="$(cd "$(dirname "$0")" && pwd)"
v8_dir="${dir}/v8"

if [ ! -d "$v8_dir" ]; then
  echo "v8 not found at $v8_dir"
  exit 1
fi

depot_tools_dir="${dir}/depot_tools"

if [ ! -d "$depot_tools_dir" ]; then
  echo "Error: depot_tools directory not found at ${depot_tools_dir}"
  exit 1
fi

export DEPOT_TOOLS_DIR="$depot_tools_dir"

PATH="${DEPOT_TOOLS_DIR}:$PATH"
export PATH

os="$(sh "${dir}/scripts/get_os.sh")"

cores="2"

if [ "$os" = "Linux" ]; then
  cores="$(grep -c processor /proc/cpuinfo)"
elif [ "$os" = "macOS" ]; then
  cores="$(sysctl -n hw.logicalcpu)"
fi

target_cpu="$(sh "${dir}/scripts/get_arch.sh")"

echo "Building V8 for $os $target_cpu"

cc_wrapper=""
if command -v ccache >/dev/null 2>&1 ; then
  cc_wrapper="ccache"
fi

gn_args="$(grep -v '^#\|^$' "${dir}/args/${os}.gn" | tr -d '\r' | tr '\n' ' ')"
gn_args="${gn_args}cc_wrapper=\"$cc_wrapper\""
gn_args="${gn_args} target_cpu=\"$target_cpu\""
gn_args="${gn_args} v8_target_cpu=\"$target_cpu\""

append_system_clang_args() {
  clang_cmd=""

  if [ "$os" = "macOS" ] && command -v xcrun >/dev/null 2>&1; then
    clang_cmd="$(xcrun -f clang++ 2>/dev/null || true)"
  fi

  if [ -z "$clang_cmd" ]; then
    clang_cmd="$(command -v clang++ 2>/dev/null || true)"
  fi

  if [ -z "$clang_cmd" ]; then
    echo "Error: clang++ not found in PATH (required to avoid Chromium clang)."
    exit 1
  fi

  clang_resource_dir="$("$clang_cmd" -print-resource-dir 2>/dev/null | tr -d '\r' | head -n 1)"
  if [ -z "$clang_resource_dir" ]; then
    echo "Error: failed to detect clang resource dir from $clang_cmd."
    exit 1
  fi

  clang_version="$(basename "$clang_resource_dir")"
  clang_base_path="$(dirname "$(dirname "$(dirname "$clang_resource_dir")")")"

  if [ ! -x "$clang_base_path/bin/clang++" ]; then
    echo "Error: resolved clang base path is invalid: $clang_base_path"
    exit 1
  fi

  echo "Using system clang: $clang_cmd"
  echo "Detected clang resource dir: $clang_resource_dir"

  gn_args="${gn_args} clang_base_path=\"$clang_base_path\""
  gn_args="${gn_args} clang_version=\"$clang_version\""
}

use_clang=true
case "$gn_args" in
  *"is_clang=false"*)
    use_clang=false
    ;;
esac

if [ "$use_clang" = "true" ] && ([ "$os" = "Linux" ] || [ "$os" = "macOS" ]); then
  append_system_clang_args
fi

cd "${dir}/v8"

# macOS runner images can rotate Xcode/SDK paths. Cached out/release
# then contains stale absolute dependencies that break ninja immediately.
if [ "$os" = "macOS" ]; then
  out_dir="./out/release"
  toolchain_stamp="${out_dir}/.apple-toolchain"
  xcode_path="$(xcode-select -p 2>/dev/null || true)"
  sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  current_toolchain="${xcode_path}|${sdk_path}"
  cached_toolchain=""

  if [ -f "$toolchain_stamp" ]; then
    cached_toolchain="$(cat "$toolchain_stamp" 2>/dev/null || true)"
  fi

  if [ -d "$out_dir" ] && [ "$cached_toolchain" != "$current_toolchain" ]; then
    echo "Apple toolchain changed or unknown in cache; cleaning ${out_dir}"
    rm -rf "$out_dir"
  fi
fi

gn gen "./out/release" --args="$gn_args"

echo "==================== Build args start ===================="
gn args "./out/release" --list | tee "${dir}/gn-args_${os}.txt"
echo "==================== Build args end ===================="

(
  set -x
  ninja -C "./out/release" -j "$cores" v8_monolith
)

if [ "$os" = "macOS" ]; then
  printf '%s\n' "$current_toolchain" > "./out/release/.apple-toolchain"
fi

ls -lh ./out/release/obj/libv8_*.a

cd -
