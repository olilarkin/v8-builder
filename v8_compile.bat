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

if "%useClang%"=="1" (
  set "clangBasePath=%V8_CLANG_BASE_PATH%"
  set "clangVersion=%V8_CLANG_VERSION%"
  set "clangResourceDir="

  if defined clangBasePath (
    if not defined clangVersion (
      echo Error: V8_CLANG_BASE_PATH is set but V8_CLANG_VERSION is missing.
      exit /b 1
    )
    set "clangBasePath=%clangBasePath:/=\%"
    for %%i in ("%clangBasePath%") do set "clangBasePath=%%~sfi"
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
    for %%i in ("%clangBasePath%") do set "clangBasePath=%%~sfi"
    set "clangBasePath=%clangBasePath:\=/%"
  )

  echo Using system clang-cl resource dir: %clangResourceDir%
  echo Using system clang base path: %clangBasePath%
  set "gnArgs=%gnArgs% clang_base_path=""%clangBasePath%"" clang_version=""%clangVersion%"""
) else (
  echo Using MSVC toolchain ^(is_clang=false^).
)

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
