$ErrorActionPreference = "Stop"
$repository = "Obliv1onis/Genzimnify"
$version = if ($env:GZIM_VERSION) { $env:GZIM_VERSION } else { "latest" }
$installRoot = if ($env:GZIM_INSTALL_ROOT) { $env:GZIM_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Genzimnify\bin" }
$base = if ($version -eq "latest") { "https://github.com/$repository/releases/latest/download" } else { "https://github.com/$repository/releases/download/$version" }
$archive = Join-Path $env:TEMP ("genzimnify-windows-x86_64-" + [guid]::NewGuid() + ".zip")
$unpack = Join-Path $env:TEMP ("genzimnify-" + [guid]::NewGuid())

Write-Host "Downloading Genzimnify $version for Windows x86_64..."
Invoke-WebRequest "$base/genzimnify-windows-x86_64.zip" -OutFile $archive
$checksums = (Invoke-WebRequest "$base/SHA256SUMS").Content
$checksumLine = $checksums -split "`n" | Where-Object { $_ -match "genzimnify-windows-x86_64\.zip\s*$" } | Select-Object -First 1
$expected = if ($checksumLine) { ($checksumLine.Trim() -split "\s+")[0] } else { $null }
$actual = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $expected -or $actual -ne $expected.ToLowerInvariant()) { throw "Genzimnify checksum verification failed" }
Expand-Archive $archive -DestinationPath $unpack -Force
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item (Join-Path $unpack "gzim.exe") $installRoot -Force
Copy-Item (Join-Path $unpack "gzim-lsp.exe") $installRoot -Force
$raylib = Join-Path $unpack "raylib.dll"
if (Test-Path $raylib) { Copy-Item $raylib $installRoot -Force }

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if (($userPath -split ";") -notcontains $installRoot) {
  [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";"), $installRoot) -join ";"), "User")
  Write-Host "Added $installRoot to your user PATH. Open a new terminal."
}
Remove-Item $archive -Force
Remove-Item $unpack -Recurse -Force
Write-Host "Installed. Run: gzim doctor"
