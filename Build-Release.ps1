#Requires -Version 5.1
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'Release'))
$ErrorActionPreference='Stop'
$version=(Get-Content (Join-Path $PSScriptRoot VERSION) -Raw).Trim()
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ExpressWindowsBuild-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $temp SqlExpressWindowsPatch
New-Item -ItemType Directory -Path $payload,$OutputDirectory -Force|Out-Null
$files=@('Start-ServerMaintenance.ps1','SqlExpress.Core.ps1','WindowsUpdate.Core.ps1','Maintenance.Core.ps1','Install.ps1','Install.cmd','Install-FromGitHub.ps1','README.md','SECURITY.md','LICENSE','VERSION')
foreach($name in $files){Copy-Item (Join-Path $PSScriptRoot $name) $payload}
$lines=foreach($name in $files){'{0} *{1}'-f(Get-FileHash (Join-Path $payload $name)).Hash,$name}
[IO.File]::WriteAllLines((Join-Path $payload 'manifest.sha256'),$lines,[Text.UTF8Encoding]::new($false))
$zip=Join-Path $OutputDirectory "SqlExpressWindowsPatch-v$version.zip"
Compress-Archive -LiteralPath $payload -DestinationPath $zip -Force
Write-Output $zip
