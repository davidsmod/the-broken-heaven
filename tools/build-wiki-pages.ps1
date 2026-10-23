param([string]$Destination = (Join-Path $PSScriptRoot '..\wiki-pages'))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination = [IO.Path]::GetFullPath($Destination)
$api = 'https://thebrokenscript.wiki.gg/api.php'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150.0.7871.250 Safari/537.36'
$cdn = 'https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/'

New-Item -ItemType Directory -Force -Path $destination | Out-Null
$manifest = Get-Content (Join-Path $root 'assets\manifests\asset-manifest.json') -Raw | ConvertFrom-Json
$byName = @{}
foreach ($asset in $manifest) { $byName[$asset.originalName.ToLowerInvariant()] = $asset }

function Get-ApiJson([string]$url) {
  $temp = [IO.Path]::GetTempFileName()
  & curl.exe -sS --fail --retry 3 -A $ua --url $url -o $temp
  if ($LASTEXITCODE -ne 0) { throw "API request failed: $url" }
  try { return ([IO.File]::ReadAllText($temp, [Text.Encoding]::UTF8) | ConvertFrom-Json) } finally { Remove-Item -LiteralPath $temp -Force }
}
function Slug([string]$title) { $s = $title.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+','-'; return $s.Trim('-') }
function CdnUrl([string]$path) { $encoded = (($path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'; return $cdn + $encoded }
function AssetUrlByName([string]$name) { $match = $byName[$name.ToLowerInvariant()]; if ($match) { return (CdnUrl $match.localPath) }; return '' }
function Html([string]$value) { return [Net.WebUtility]::HtmlEncode($value) }
function RichHtml([string]$value) { $encoded = Html $value; return $encoded.Replace('TB_BOLD_START','<strong>').Replace('TB_BOLD_END','</strong>').Replace('TB_ITALIC_START','<em>').Replace('TB_ITALIC_END','</em>') }
function TextToHtml([string]$text) {
  $text = $text -replace '\{\{[^{}]*\}\}',''
  while ($text -match '\{\{[^{}]*\}\}') { $text = $text -replace '\{\{[^{}]*\}\}','' }
  $text = $text -replace '\[\[(?:File|Image):[^\]]+\]\]','' -replace '\[\[([^\]|]+)\|([^\]]+)\]\]','$2' -replace '\[\[([^\]]+)\]\]','$1' -replace '\[([^\s\]]+)\s+([^\]]+)\]','$2' -replace "'''([^']+)'''",'TB_BOLD_START$1TB_BOLD_END' -replace "''([^']+)''",'TB_ITALIC_START$1TB_ITALIC_END' -replace "'''|''",'' -replace '<[^>]+>',''
  $parts = @(); $paragraph = @()
  foreach ($line in ($text -split "`r?`n")) {
    $line = $line.Trim()
    if (!$line) { continue }
    if ($line -match '^(frameless|thumb|none\|.*)$') { continue }
    if ($line -match '^={2,}\s*(.*?)\s*={2,}$') { if ($paragraph.Count) { $parts += '<p>' + (RichHtml ($paragraph -join ' ')) + '</p>'; $paragraph=@() }; $parts += '<h2>' + (RichHtml $Matches[1]) + '</h2>' }
    elseif ($line.StartsWith('*')) { if ($paragraph.Count) { $parts += '<p>' + (RichHtml ($paragraph -join ' ')) + '</p>'; $paragraph=@() }; $parts += '<p class="bullet">' + (RichHtml $line.TrimStart('*').Trim()) + '</p>' }
    else { $paragraph += $line }
  }
  if ($paragraph.Count) { $parts += '<p>' + (RichHtml ($paragraph -join ' ')) + '</p>' }
  if (!$parts) { return '<p class="muted">No text is documented for this entry yet.</p>' }
  return ($parts -join "`n")
}

$pages = @()
$all = Get-ApiJson ($api + '?action=query&list=allpages&apnamespace=0&aplimit=500&format=json')
$titles = @($all.query.allpages | ForEach-Object title)
for ($i=0; $i -lt $titles.Count; $i += 20) {
  $chunk = $titles[$i..([Math]::Min($i + 19, $titles.Count - 1))]
  $encoded = [Uri]::EscapeDataString(($chunk -join '|'))
  $url = "${api}?action=query&prop=revisions%7Cimages&rvprop=content&rvslots=main&imlimit=max&format=json&formatversion=2&titles=$encoded"
  $result = Get-ApiJson $url
  foreach ($record in @($result.query.pages)) {
    $title = [string]$record.PSObject.Properties['title'].Value
    $slug = Slug $title
    $assets = @()
    foreach ($image in @($record.images)) {
      $name = ([string]$image.title) -replace '^File:',''
      $match = $byName[$name.ToLowerInvariant()]
      if ($match) { $assets += [ordered]@{type=($(if($match.category -eq 'audio'){'audio'}else{'image'})); name=$name; path=$match.localPath; url=(CdnUrl $match.localPath)} }
    }
    $tokens = @($title.ToLowerInvariant() -split '[^\p{L}\p{Nd}]+' | Where-Object {$_.Length -ge 4})
    foreach ($asset in $manifest) {
      if ($assets.Count -ge 12) { break }
      $lower = $asset.originalName.ToLowerInvariant()
      if ($tokens | Where-Object {$lower.Contains($_)}) {
        if (!($assets.name -contains $asset.originalName)) { $assets += [ordered]@{type=($(if($asset.category -eq 'audio'){'audio'}else{'image'})); name=$asset.originalName; path=$asset.localPath; url=(CdnUrl $asset.localPath)} }
      }
    }
    $content = ''
    if ($record.revisions -and $record.revisions[0].slots.main.content) { $content = [string]$record.revisions[0].slots.main.content }
    $categories = @([regex]::Matches($content, '(?im)\[\[Category:([^\]|]+)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique)
    if (!$categories) { $categories = @('Uncategorized') }
    $pages += [ordered]@{title=$title; slug=$slug; extract=$content; source=('https://thebrokenscript.wiki.gg/wiki/' + [Uri]::EscapeDataString($title.Replace(' ','_'))); assets=$assets; categories=$categories}
  }
}

$pages = @($pages | Sort-Object { $_['title'] } -Unique)
$data = [ordered]@{generated=(Get-Date).ToUniversalTime().ToString('o'); source='https://thebrokenscript.wiki.gg/'; pages=$pages}
$data | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $destination 'wiki-data.json')

$indexCards = foreach ($page in $pages) { $preview = (TextToHtml $page.extract) -replace '<[^>]+>',' ' -replace '\s+',' '; $preview = $preview.Trim(); $search = $page.title + ' ' + $page.extract; $search = $search.Substring(0,[Math]::Min(5000,$search.Length)); $categoryClass = (($page.categories | ForEach-Object { Slug $_ }) -join ' '); '<a class="entry-card" data-categories="' + $categoryClass + '" data-search="' + (Html $search) + '" href="./' + $page.slug + '.html"><b>' + (Html $page.title) + '</b><span>' + $preview.Substring(0,[Math]::Min(220,$preview.Length)) + '...</span><i>OPEN -></i></a>' }
$categoryNames = @($pages | ForEach-Object { $_.categories } | Sort-Object -Unique)
$categoryButtons = '<button class="category-filter active" data-category="all" type="button">ALL</button>' + (($categoryNames | ForEach-Object { '<button class="category-filter" data-category="' + (Slug $_) + '" type="button">' + (Html $_) + '</button>' }) -join '')
$sections = @(
  [ordered]@{title='Lore'; slug='lore'; image='LoreButton.png'},
  [ordered]@{title='Entities'; slug='entities'; image='Entity_button_base.png'},
  [ordered]@{title='Random Events'; slug='random-events'; image='Events_button_base.png'},
  [ordered]@{title='Structures'; slug='structures'; image='Structures_button_base.png'},
  [ordered]@{title='Items'; slug='items'; image='ItemsButton.png'},
  [ordered]@{title='Dimensions'; slug='dimensions'; image='DimensionsButton.png'},
  [ordered]@{title='Mechanics'; slug='mechanics'; image='MechanicsButton.png'},
  [ordered]@{title='ARG'; slug='arg'; image='ARGButton.png'}
)
$sectionCards = foreach ($section in $sections) { $imageUrl = AssetUrlByName $section.image; '<a class="wiki-section-card" href="./' + $section.slug + '.html">' + $(if ($imageUrl) { '<img src="' + $imageUrl + '" alt="">' }) + '<strong>' + $section.title + '</strong><span>Open documentation</span></a>' }
$index = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TBS // LOCAL DATABASE</title><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/style.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-pages.css"></head><body><main class="wiki-index"><p class="overline">LOCAL DATABASE // $($pages.Count) ENTRIES</p><h1>THE BROKEN SCRIPT<br><em>ARCHIVE INDEX</em></h1><p class="lead">Pages generated from the community wiki. Images and audio are served from GitHub through jsDelivr.</p><input id="filter" placeholder="Search an entry..." aria-label="Search an entry"><div class="entry-grid">$($indexCards -join "`n")</div><a class="back-link" href="./index.html"><- Archive index</a></main><script>const f=document.querySelector('#filter');f.oninput=()=>document.querySelectorAll('.entry-card').forEach(c=>c.hidden=!c.textContent.toLowerCase().includes(f.value.toLowerCase()));</script></body></html>
"@
$index = $index.Replace('<h1>THE BROKEN SCRIPT<br><em>ARCHIVE INDEX</em></h1>', '<div class="index-heading"><img class="home-logo" src="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/assets/images/0073_Boob_(my_friend_named_this).png" alt="The Broken Script logo" width="96" height="96"><h1>THE BROKEN SCRIPT<br><em>ARCHIVE INDEX</em></h1>')
$index = $index.Replace('</h1><p class="lead">', '</h1></div><p class="lead">')
$index = $index.Replace('<input id="filter"', '<section class="wiki-sections"><h2>DOCUMENTATION</h2><div class="wiki-section-grid">' + ($sectionCards -join '') + '</div></section><div class="category-bar">' + $categoryButtons + '</div><input id="filter"')
$index = $index.Replace('</head>', '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-overrides.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/fonts.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/official-theme.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/animations.css"></head>')
$index = $index.Replace('</title>', '</title><link rel="icon" type="image/x-icon" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/assets/images/1371_Site-favicon.ico">')
$index = $index.Replace("c.textContent.toLowerCase().includes(f.value.toLowerCase())", "c.dataset.search.toLowerCase().includes(f.value.toLowerCase())")
$index = $index.Replace("const f=document.querySelector('#filter');f.oninput=()=>document.querySelectorAll('.entry-card').forEach(c=>c.hidden=!c.dataset.search.toLowerCase().includes(f.value.toLowerCase()));", "const f=document.querySelector('#filter');let active='all';const refresh=()=>document.querySelectorAll('.entry-card').forEach(c=>c.hidden=!(c.dataset.search.toLowerCase().includes(f.value.toLowerCase())&&(active==='all'||c.dataset.categories.split(' ').includes(active))));f.oninput=refresh;document.querySelectorAll('.category-filter').forEach(b=>b.onclick=()=>{active=b.dataset.category;document.querySelectorAll('.category-filter').forEach(x=>x.classList.toggle('active',x===b));refresh();});")
$index = $index.Replace('href="../index.html"><- Back to terminal', 'href="./index.html"><- Archive index')
$index = $index.Replace('</body></html>', '<script src="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-pages.js"></script></body></html>')
$index | Set-Content -Encoding UTF8 (Join-Path $destination 'index.html')

foreach ($page in $pages) {
  $media = foreach ($asset in @($page.assets)) {
    if ($asset.type -eq 'audio') { '<audio controls preload="none" src="' + $asset.url + '"></audio>' }
    else { '<figure><img loading="lazy" src="' + $asset.url + '" alt="' + (Html $asset.name) + '"><figcaption>' + (Html $asset.name) + '</figcaption></figure>' }
  }
  $html = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$((Html $page.title)) // TBS</title><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/style.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-pages.css"></head><body><main class="entry-page"><header><a class="back-link" href="./index.html"><- ARCHIVE INDEX</a><span class="entry-code">ENTRY // $($page.slug.ToUpperInvariant())</span></header><h1>$((Html $page.title))</h1><p class="source-line">SOURCE MIRROR // <a href="$($page.source)" target="_blank" rel="noopener">official wiki -></a></p><article class="entry-copy">$(TextToHtml $page.extract)</article><section class="media-section"><h2>ASSOCIATED RESOURCES</h2><div class="media-grid">$($media -join "`n")</div></section><footer><a href="./index.html"><- All entries</a> | <a href="./index.html">Archive index</a></footer></main><script src="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-pages.js"></script></body></html>
"@
  $html = $html.Replace('</head>', '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/wiki-overrides.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/fonts.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/official-theme.css"><link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/wiki-pages/animations.css"></head>')
  $html = $html.Replace('</title>', '</title><link rel="icon" type="image/x-icon" href="https://cdn.jsdelivr.net/gh/davidsmod/the-broken-wiki@c07372135c84ef782ebbf9f1a188b44194eefb63/assets/images/1371_Site-favicon.ico">')
  $html = $html.Replace('href="../index.html">Terminal', 'href="./index.html">Archive index')
  $html | Set-Content -Encoding UTF8 (Join-Path $destination ($page.slug + '.html'))
}
Write-Host "Generated $($pages.Count) local wiki pages in $destination"


