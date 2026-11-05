# Shared helpers for the Windows scripts.

function Import-VsEnv([string] $VcArch) {
  $vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $bat = "$vs\VC\Auxiliary\Build\vcvarsall.bat"
  cmd /c "`"$bat`" $VcArch >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item "env:$($Matches[1])" $Matches[2] }
  }
}

function Get-File([string] $Url, [string] $Path) {
  if (-not (Test-Path $Path)) {
    for ($i = 1; $i -le 3; $i++) {
      try { Invoke-WebRequest $Url -OutFile $Path -UseBasicParsing; return } catch { Start-Sleep 5 }
    }
    throw "download failed: $Url"
  }
}

function Test-Sha256([string] $Path, [string] $Sha) {
  $h = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $Sha.ToLower()) { throw "sha256 mismatch for $Path ($h)" }
}

# openssl-<version> folder, checked with the sha256 published with the release
function Get-OpenSSLSource([string] $Version, [string] $Work) {
  $name = "openssl-$Version"
  $tag = if ($Version -like '1.*') { 'OpenSSL_' + ($Version -replace '\.', '_') } else { $name }
  $tgz = "$Work\$name.tar.gz"
  Get-File "https://github.com/openssl/openssl/releases/download/$tag/$name.tar.gz" $tgz
  if ($Version -eq '1.1.1w') {
    $sha = 'cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8'
  } else {
    Get-File "https://github.com/openssl/openssl/releases/download/$tag/$name.tar.gz.sha256" "$tgz.sha256"
    $sha = ((Get-Content "$tgz.sha256" -Raw).Trim() -split '\s+')[0]
  }
  Test-Sha256 $tgz $sha
  if (-not (Test-Path "$Work\$name")) { tar -xzf $tgz -C $Work }
  return "$Work\$name"
}

function Get-HunspellSource([string] $Work) {
  $tgz = "$Work\hunspell-1.7.2.tar.gz"
  Get-File 'https://github.com/hunspell/hunspell/releases/download/v1.7.2/hunspell-1.7.2.tar.gz' $tgz
  Test-Sha256 $tgz '11ddfa39afe28c28539fe65fc4f1592d410c1e9b6dd7d8a91ca25d85e9ec65b8'
  if (-not (Test-Path "$Work\hunspell-1.7.2")) { tar -xzf $tgz -C $Work }
  return "$Work\hunspell-1.7.2"
}
