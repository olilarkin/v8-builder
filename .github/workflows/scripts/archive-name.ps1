
$arch = $Env:RUNNER_ARCH

if ($Env:TARGET_CPU) {
  $arch = $Env:TARGET_CPU
}

switch ($arch.ToUpper()) {
  "AMD64" { $arch = "x64" }
  "AARCH64" { $arch = "arm64" }
  default { $arch = $arch.ToLower() }
}

$archiveName = "v8_$Env:RUNNER_OS`_$arch"

Write-Host "Using Archive Name: $archiveName"

Write-Output "ARCHIVE_NAME=$archiveName" | Out-File -FilePath "$Env:GITHUB_ENV" -Encoding utf8
