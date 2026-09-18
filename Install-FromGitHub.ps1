#Requires -Version 5.1
#Requires -RunAsAdministrator
param([string]$Destination='C:\SqlExpressWindowsPatch')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$headers=@{'User-Agent'='SqlExpressWindowsPatch';Accept='application/vnd.github+json'}
$release=Invoke-RestMethod 'https://api.github.com/repos/zymbytskyi/sql-express-windows-maintenance/releases/latest' -Headers $headers
if($release.draft-or$release.prerelease){throw 'Only stable published releases are accepted.'}
$assets=@($release.assets|Where-Object{$_.name-match'^SqlExpressWindowsPatch-v\d+\.\d+\.\d+\.zip$'})
if($assets.Count-ne1){throw 'Expected one release ZIP.'}
$asset=$assets[0]
if($asset.digest-notmatch'^sha256:([A-Fa-f0-9]{64})$'){throw 'GitHub release digest missing.'}
$expected=$matches[1]
$temp=Join-Path $env:TEMP ('ExpressWindowsDownload-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$zip=Join-Path $temp $asset.name
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest $asset.browser_download_url -Headers $headers -UseBasicParsing -OutFile $zip
if((Get-FileHash $zip).Hash-ne$expected){throw 'Release SHA-256 mismatch.'}
Write-Host 'SHA-256 verified; extracting...'
Expand-Archive $zip (Join-Path $temp Extracted)
& (Join-Path $temp 'Extracted\SqlExpressWindowsPatch\Install.ps1') -Destination $Destination
