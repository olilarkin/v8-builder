#!/bin/sh

set -e

arch=""

if [ -n "$TARGET_CPU" ]; then
  case "$(echo "$TARGET_CPU" | tr '[:upper:]' '[:lower:]')" in
    x86|i386|i486|i586|i686)
      arch="x86"
      ;;
    x64|amd64|x86_64)
      arch="x64"
      ;;
    arm64|aarch64|armv8*)
      arch="arm64"
      ;;
    arm|armv6*|armv7*)
      arch="arm"
      ;;
    *)
      ;;
  esac
fi

# X86, X64, ARM, or ARM64
if [ -z "$arch" ] && [ -n "$RUNNER_ARCH" ]; then
  arch="$(echo "$RUNNER_ARCH" | tr '[:upper:]' '[:lower:]')"
elif [ -z "$arch" ]; then
  case "$(uname -m)" in
    x86_64|amd64)
      arch="x64"
      ;;
    x86|i386|i486|i586|i686)
      arch="x86"
      ;;
    arm64|aarch64|armv8*)
      arch="arm64"
      ;;
    arm|armv6*|armv7*)
      arch="arm"
      ;;
    *)
      ;;
  esac
fi

if [ -z "$arch" ]; then
  echo "Unknown architecture type" >&2
  exit 1
fi

echo "$arch"
