@echo off
setlocal enabledelayedexpansion

set "lib_path=%~1"

if "%lib_path%"=="" (
  echo Usage: %~0 ^<path-to-v8_monolith.lib^>
  exit /b 1
)

if not exist "%lib_path%" (
  echo Error: %lib_path% not found
  exit /b 1
)

where llvm-ar >nul 2>nul
if errorlevel 1 (
  echo Error: llvm-ar not found
  exit /b 1
)

set "tmpdir=%TEMP%\v8_deconflict_%RANDOM%"
mkdir "%tmpdir%" 2>nul

echo Deconflicting %lib_path%...

REM Step 1: Extract all .obj files
pushd "%tmpdir%"
llvm-ar x "%lib_path%"
if errorlevel 1 (
  echo Error: failed to extract archive
  popd
  rmdir /s /q "%tmpdir%"
  exit /b 1
)

REM Step 2: Remove abseil and zlib .obj files
set "removed=0"
for %%f in (*absl*.obj *zlib*.obj *adler32*.obj *crc32*.obj *deflate*.obj *inflate*.obj) do (
  if exist "%%f" (
    del "%%f"
    set /a removed+=1
  )
)
echo Removed !removed! conflicting .obj files

REM Step 3: Re-create archive with remaining .obj files
del "%lib_path%"
for %%f in (*.obj) do (
  llvm-ar rcs "%lib_path%" "%%f"
)

popd
rmdir /s /q "%tmpdir%"

echo Deconflicted: %lib_path%
endlocal
