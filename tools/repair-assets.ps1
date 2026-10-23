$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $root 'assets\manifests\asset-manifest.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$audioExt = @('.mp3','.ogg','.wav','.flac','.m4a')
$audioDir = Join-Path $root 'assets\audio'
New-Item -ItemType Directory -Force -Path $audioDir | Out-Null

foreach ($item in $manifest) {
  $name = [IO.Path]::GetFileName($item.localPath)
  $current = Join-Path $root ($item.localPath -replace '/','\')
  if ($item.mime -like 'audio/*' -or $item.mime -eq 'application/ogg' -or $audioExt -contains ([IO.Path]::GetExtension($name).ToLowerInvariant())) {
    $targetPath = Join-Path $audioDir $name
    if ((Test-Path -LiteralPath $current) -and ($current -ne $targetPath)) { Move-Item -LiteralPath $current -Destination $targetPath -Force }
    $item.category = 'audio'
    $item.localPath = 'assets/audio/' + $name
  }
}

$agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.7871.250 Safari/537.36'
$missing = @($manifest | Where-Object { !(Test-Path -LiteralPath (Join-Path $root ($_.localPath -replace '/','\'))) })
foreach ($item in $missing) {
  $path = Join-Path $root ($item.localPath -replace '/','\')
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  & curl.exe -L --fail --retry 5 --retry-delay 2 --silent --show-error -A $agent -o $path ($item.source)
  if ($LASTEXITCODE -ne 0) { Write-Warning "Failed: $($item.originalName)" }
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $manifestPath
Write-Host "Repaired $($missing.Count) missing files. Audio files: $((Get-ChildItem $audioDir -File).Count)."
