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

set "tmpdir=%TEMP%\v8_deconflict_%RANDOM%"
mkdir "%tmpdir%" 2>nul

echo Deconflicting %lib_path%...

where llvm-ar >nul 2>nul
if not errorlevel 1 (
  call :deconflict_with_llvm_ar
  set "rc=!errorlevel!"
) else (
  call :deconflict_with_lib
  set "rc=!errorlevel!"
)

if exist "%tmpdir%" rmdir /s /q "%tmpdir%"

if not "%rc%"=="0" (
  exit /b %rc%
)

echo Deconflicted: %lib_path%
endlocal
exit /b 0

:deconflict_with_llvm_ar
pushd "%tmpdir%"
llvm-ar x "%lib_path%"
if errorlevel 1 (
  echo Error: failed to extract archive with llvm-ar
  popd
  exit /b 1
)

set "removed=0"
for %%f in (*absl*.obj *zlib*.obj *adler32*.obj *crc32*.obj *deflate*.obj *inflate*.obj) do (
  if exist "%%f" (
    del "%%f"
    set /a removed+=1
  )
)
echo Removed !removed! conflicting .obj files

del "%lib_path%"
for %%f in (*.obj) do (
  llvm-ar rcs "%lib_path%" "%%f"
  if errorlevel 1 (
    echo Error: failed to rebuild archive with llvm-ar
    popd
    exit /b 1
  )
)

popd
exit /b 0

:deconflict_with_lib
where lib >nul 2>nul
if errorlevel 1 (
  echo Error: neither llvm-ar nor lib.exe found
  exit /b 1
)

pushd "%tmpdir%"

set /a removed=0
set /a kept=0

for /f "delims=" %%f in ('lib /nologo /list "%lib_path%"') do (
  set "obj=%%f"
  if /I "!obj:~-4!"==".obj" (
    echo(!obj! | findstr /I /R "absl zlib adler32 crc32 deflate inflate" >nul
    if errorlevel 1 (
      lib /nologo /extract:"!obj!" "%lib_path%" >nul
      if errorlevel 1 (
        echo Error: failed to extract !obj! with lib.exe
        popd
        exit /b 1
      )
      set /a kept+=1
    ) else (
      set /a removed+=1
    )
  )
)

echo Removed !removed! conflicting .obj files

if !kept! EQU 0 (
  echo Error: no object files left after deconflict
  popd
  exit /b 1
)

del "%lib_path%"

(for %%f in (*.obj) do @echo %%f) > objs.rsp
lib /nologo /out:"%lib_path%" @objs.rsp >nul
if errorlevel 1 (
  echo Error: failed to rebuild archive with lib.exe
  popd
  exit /b 1
)

popd
exit /b 0
