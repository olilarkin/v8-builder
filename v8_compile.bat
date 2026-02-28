@echo off

setlocal

set "dir=%~dp0"
set "v8Dir=%dir%\v8"

if not exist "%v8Dir%" (
  echo V8 not found at %v8Dir%
  exit /b 1
)

set "depotToolsDir=%dir%\depot_tools"

if not exist "%depotToolsDir%" (
  echo Error: depot_tools directory not found at %depotToolsDir%
  exit /b 1
)

set "DEPOT_TOOLS_DIR=%depotToolsDir%"
set "DEPOT_TOOLS_WIN_TOOLCHAIN=0"

set "Path=%DEPOT_TOOLS_DIR%;%Path%"

for /F "delims=" %%i in ('call "%dir%\scripts\get_os.bat"') do (
  set "os=%%i"
)

for /F "delims=" %%i in ('call "%dir%\scripts\get_arch.bat"') do (
  set "targetCpu=%%i"
)

echo Building V8 for %os% %targetCpu%

call :apply_backing_store_windows_patch "%v8Dir%\src\objects\backing-store.cc"
if errorlevel 1 exit /b %errorlevel%

setlocal EnableDelayedExpansion

set "args="

for /F "usebackq eol=# tokens=*" %%i in ("%dir%\args\%os%.gn") do (
  set "args=!args!%%i "
)

endlocal & set "gnArgs=%args%"

set "ccWrapper="

set "gnArgs=%gnArgs%cc_wrapper=""%ccWrapper%"""
set "gnArgs=%gnArgs% target_cpu=""%targetCpu%"""
set "gnArgs=%gnArgs% v8_target_cpu=""%targetCpu%"""

set "useClang=1"
echo %gnArgs% | findstr /I "is_clang=false" >nul
if not errorlevel 1 (
  set "useClang=0"
)

if "%useClang%"=="1" goto :configure_clang

echo Using MSVC toolchain ^(is_clang=false^).
goto :after_toolchain

:configure_clang
set "clangBasePath=%V8_CLANG_BASE_PATH%"
set "clangVersion=%V8_CLANG_VERSION%"
set "clangResourceDir="

if defined clangBasePath (
  if not defined clangVersion (
    echo Error: V8_CLANG_BASE_PATH is set but V8_CLANG_VERSION is missing.
    exit /b 1
  )
  set "clangBasePath=%clangBasePath:/=\%"
  set "clangBasePath=%clangBasePath:\=/%"
  set "clangResourceDir=%clangBasePath%/lib/clang/%clangVersion%"
) else (
  for /F "delims=" %%i in ('clang-cl -print-resource-dir 2^>nul') do set "clangResourceDir=%%i"

  if not defined clangResourceDir (
    echo Error: clang-cl not found in PATH ^(required when is_clang=true^).
    exit /b 1
  )

  for %%i in ("%clangResourceDir%") do set "clangVersion=%%~nxi"
  for %%i in ("%clangResourceDir%\..\..\..") do set "clangBasePath=%%~fi"
  set "clangBasePath=%clangBasePath:/=\%"
  set "clangBasePath=%clangBasePath:\=/%"
)

if not defined clangBasePath (
  echo Error: failed to resolve clang base path.
  exit /b 1
)

if not defined clangVersion (
  echo Error: failed to resolve clang version.
  exit /b 1
)

if not defined clangResourceDir (
  echo Error: failed to resolve clang resource dir.
  exit /b 1
)

echo Using system clang-cl resource dir: %clangResourceDir%
echo Using system clang base path: %clangBasePath%
set "gnArgs=%gnArgs% clang_base_path=""%clangBasePath%"" clang_version=""%clangVersion%"""

:after_toolchain

pushd "%dir%\v8"

call gn gen ".\out\release" --args="%gnArgs%"
if errorlevel 1 (
  echo Failed to generate build files.
  exit /b %errorlevel%
)

echo ==================== Build args start ====================
call gn args ".\out\release" --list > "%dir%\gn-args_%os%.txt"
type "%dir%\gn-args_%os%.txt"
echo ==================== Build args end ====================

call ninja -C ".\out\release" -j %NUMBER_OF_PROCESSORS% v8_monolith
if errorlevel 1 (
  echo Build failed.
  exit /b %errorlevel%
)

dir ".\out\release\obj\v8_*.lib"

popd

endlocal
exit /b 0

:apply_backing_store_windows_patch
setlocal
set "sourcePath=%~1"

if not exist "%sourcePath%" (
  echo Warning: source patch target not found: %sourcePath%
  endlocal & exit /b 0
)

findstr /C:"const std::function<bool()>& fn" "%sourcePath%" >nul
if errorlevel 1 (
  endlocal & exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = '%sourcePath%'; $old = 'const std::function<bool()>& fn'; $new = 'const auto& fn'; $content = [System.IO.File]::ReadAllText($p); if ($content.Contains($old)) { $updated = $content.Replace($old, $new); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($p, $updated, $utf8NoBom) }"
if errorlevel 1 (
  echo Error: failed to apply backing-store compatibility patch.
  endlocal & exit /b 1
)

echo Applied backing-store compatibility patch for FunctionRef on Windows.
endlocal & exit /b 0
