# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automated V8 JavaScript engine builder that compiles V8 into a monolithic static library (`libv8_monolith.a` / `v8_monolith.lib`) for Linux, macOS, and Windows across multiple architectures (x64, ARM64). Uses GitHub Actions for CI/CD and tracks the latest stable Chromium V8 version automatically.

The current V8 version is stored in the `VERSION` file (currently 14.5.201.7).

## Build Pipeline

The build follows four sequential steps, each with `.sh` (Unix) and `.bat` (Windows) variants:

1. **`v8_download`** - Runs `gclient sync` to fetch V8 source at the version in `VERSION`
2. **`v8_compile`** - Generates build files with `gn gen` using platform args from `args/*.gn`, then builds with `ninja -C ./out/release v8_monolith`
3. **`v8_test`** - Compiles and runs V8's hello-world sample against the built library
4. **`archive`** - Packages headers + library into `v8_<OS>_<ARCH>.tar.xz` (Unix) or `.7z` (Windows)

`depot_tools` (git submodule) provides `gclient`, `gn`, and `ninja`.

## CI/CD Workflows

- **`v8-build-test.yml`** - Triggers on push to `master`/`actions` branches. Builds on ubuntu-latest, macos-13, macos-latest, windows-latest. Uses composite actions in `.github/actions/build-{linux,macos,windows}/`.
- **`v8-release.yml`** - Triggers on `v*` tags. Same build matrix, then uploads artifacts to GitHub Releases. Only runs on `kuoruan` repo.
- **`v8-version-check.yml`** - Daily cron (1:00 UTC). Queries chromiumdash.appspot.com for latest stable Chromium, extracts V8 version. If new: updates `depot_tools` submodule, writes `VERSION`, commits, tags, and pushes (triggering release).

Use `gh run list` to check CI status after modifying workflow files.

## GN Build Configuration

All platforms share the same core args in `args/{Linux,macOS,Windows}.gn`:
- Release build, monolithic (not component), no i18n, no test features
- Embedded startup data, stripped symbols
- `cc_wrapper` is set dynamically (ccache on Unix, sccache on Windows)
- `target_cpu` and `v8_target_cpu` are set from detected architecture

## Commit Conventions

Commits follow this pattern (no co-author sign-off):
- `chore(v8): bump to v<version>`
- `chore(depot_tools): update to latest`
