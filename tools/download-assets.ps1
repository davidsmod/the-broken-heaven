param(
  [string]$Destination = (Join-Path $PSScriptRoot '..\assets'),
  [int]$Parallel = 8
)

$ErrorActionPreference = 'Stop'
$destination = [IO.Path]::GetFullPath($Destination)
$userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.7871.250 Safari/537.36'
$apiBase = 'https://thebrokenscript.wiki.gg/api.php?action=query&list=allimages&ailimit=500&aiprop=url%7Csize%7Cmime%7Ctimestamp&format=json'

foreach ($folder in @('images','audio','video','other','manifests')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $destination $folder) | Out-Null
}

function Get-SafeName([string]$name) {
  $safe = $name -replace '[<>:"/\\|?*]', '_'
  $safe = $safe.Trim().TrimEnd('.')
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unnamed' }
  return $safe
}

$files = [Collections.Generic.List[object]]::new()
$continue = $null
do {
  $apiUrl = $apiBase
  if ($continue) { $apiUrl += '&aicontinue=' + [Uri]::EscapeDataString($continue) }
  $json = & curl.exe -sS --fail -A $userAgent $apiUrl | ConvertFrom-Json
  foreach ($file in $json.query.allimages) { $files.Add($file) }
  $continue = $json.continue.aicontinue
} while ($continue)

$manifest = [Collections.Generic.List[object]]::new()
$curlConfig = Join-Path $destination 'manifests\download-assets.curl'
$configLines = [Collections.Generic.List[string]]::new()
$index = 0

foreach ($file in $files) {
  $index++
  $mime = [string]$file.mime
  if ($mime -like 'image/*') { $category = 'images' }
  elseif ($mime -like 'audio/*' -or $mime -eq 'application/ogg') { $category = 'audio' }
  elseif ($mime -like 'video/*') { $category = 'video' }
  else { $category = 'other' }
  $safeName = Get-SafeName $file.name
  $localName = '{0:D4}_{1}' -f $index, $safeName
  $localRelative = Join-Path $category $localName
  $localAbsolute = [IO.Path]::GetFullPath((Join-Path $destination $localRelative))
  $source = "$($file.url)&format=original"
  $manifest.Add([ordered]@{
    index = $index
    originalName = $file.name
    localPath = ('assets/' + ($localRelative -replace '\\','/'))
    category = $category
    mime = $mime
    size = [int64]$file.size
    timestamp = $file.timestamp
    source = $source
    page = $file.descriptionurl
    license = 'CC BY-SA 4.0 unless otherwise noted on the source page'
  })
  $configLines.Add(('url = "{0}"' -f $source))
  $configLines.Add(('output = "{0}"' -f ($localAbsolute -replace '\\','/')))
}

$manifestPath = Join-Path $destination 'manifests\asset-manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $manifestPath
$configLines | Set-Content -Encoding ASCII $curlConfig
$readme = @"
# The Broken Script assets

Assets collected from https://thebrokenscript.wiki.gg/ on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz').

- `asset-manifest.json` contains the original filename, source page, MIME type, size and local path.
- Files are grouped under `images/`, `audio/`, `video/` and `other/`.
- Media remains subject to the license and attribution shown on its source page. The wiki footer states CC BY-SA 4.0 unless otherwise noted.
"@
$readme | Set-Content -Encoding UTF8 (Join-Path $destination 'README.md')

Write-Host ("Catalogued {0} files ({1:N2} GB). Starting parallel download..." -f $files.Count, (($files | Measure-Object -Property size -Sum).Sum / 1GB))
& curl.exe --parallel --parallel-max $Parallel --fail --retry 3 --retry-delay 1 --silent --show-error -A $userAgent --config $curlConfig
if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE" }
Write-Host 'Download complete.'
