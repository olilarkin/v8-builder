#!/bin/sh

arch="${TARGET_CPU:-$RUNNER_ARCH}"
arch="$(echo "$arch" | tr '[:upper:]' '[:lower:]')"

case "$arch" in
  amd64)
    arch="x64"
    ;;
  aarch64)
    arch="arm64"
    ;;
esac

archive_name="v8_${RUNNER_OS}_${arch}"

echo "Using Archive Name: $archive_name"

echo "ARCHIVE_NAME=$archive_name" >> "$GITHUB_ENV"
