# Builds OpenSSL (shared, static CRT) and Hunspell for Windows with MSVC.
# Usage: scripts/win-build.ps1 -OpenSSL 3.5.4 -Arch x64|arm64 -Out <folder>
# Needs Visual Studio (C++), Strawberry Perl and, for x64, NASM.
param(
  [Parameter(Mandatory)] [string] $OpenSSL,
  [Parameter(Mandatory)] [ValidateSet('x64', 'arm64')] [string] $Arch,
  [Parameter(Mandatory)] [string] $Out,
  [string] $Work = "$PWD\work-$Arch"
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot
. "$PSScriptRoot\common.ps1"

New-Item -ItemType Directory -Force $Work, $Out | Out-Null
$Out = (Resolve-Path $Out).Path

# MSVC environment (cross for arm64)
Import-VsEnv $(if ($Arch -eq 'x64') { 'x64' } else { 'x64_arm64' })

# --- OpenSSL
$src = Get-OpenSSLSource $OpenSSL $Work
Push-Location $src
$target = if ($Arch -eq 'x64') { 'VC-WIN64A' } else { 'VC-WIN64-ARM' }
$opts = @('shared', 'no-tests', "--prefix=$Work\inst", "--openssldir=$Work\ssl")
if ($Arch -eq 'arm64') { $opts += 'no-asm' }
perl Configure $target @opts
if ($LASTEXITCODE) { throw "Configure failed" }
# static CRT: the DLLs don't need the Visual C++ runtime (also on Windows 7)
(Get-Content makefile) -replace '/MD\b', '/MT' | Set-Content makefile
nmake /nologo build_libs
if ($LASTEXITCODE) { throw "nmake failed" }
Copy-Item libssl-*.dll, libcrypto-*.dll $Out
Pop-Location

# --- Hunspell (Tero loads it as libhunspellx64.dll, also on ARM64)
$hs = Get-HunspellSource $Work
Push-Location "$hs\src\hunspell"
cl /nologo /O2 /MT /EHsc /DBUILDING_LIBHUNSPELL /LD *.cxx "/Fe:$Out\libhunspellx64.dll" /link /DLL
if ($LASTEXITCODE) { throw "hunspell build failed" }
Remove-Item "$Out\libhunspellx64.exp", "$Out\libhunspellx64.lib" -ErrorAction SilentlyContinue
Pop-Location

# --- licenses
Copy-Item (Get-ChildItem "$src\LICENSE*" | Select-Object -First 1).FullName "$Out\LICENSE-OpenSSL.txt"
Copy-Item "$hs\COPYING.MPL" "$Out\LICENSE-Hunspell-MPL.txt"

# --- test program
cl /nologo /O2 /MT "$Root\tests\libtest.c" "/Fe:$Work\libtest-$Arch.exe"
if ($LASTEXITCODE) { throw "libtest build failed" }

# --- checks: no Visual C++ runtime, nothing newer than Windows 7 (x64)
$bad = 0
foreach ($dll in Get-ChildItem "$Out\*.dll") {
  $deps = dumpbin /nologo /dependents $dll.FullName | Out-String
  if ($deps -match '(?i)vcruntime|msvcp|api-ms-win-crt') { Write-Host "BAD $($dll.Name) needs the Visual C++ runtime"; $bad = 1 }
  if ($Arch -eq 'x64') {
    $imps = dumpbin /nologo /imports $dll.FullName | Out-String
    foreach ($f in 'GetSystemTimePreciseAsFileTime', 'SetThreadDescription', 'CreateFile2', 'WaitOnAddress', 'PrefetchVirtualMemory') {
      if ($imps -match "\b$f\b") { Write-Host "BAD $($dll.Name) imports $f (Windows 8+)"; $bad = 1 }
    }
  }
  Write-Host "ok   $($dll.Name)"
}
if ($bad) { throw "checks failed" }
Get-ChildItem $Out
