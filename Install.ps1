#Requires -Version 5.1
#Requires -RunAsAdministrator
param([string]$Destination='C:\SqlExpressWindowsPatch')
$ErrorActionPreference='Stop'
$resolved=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
if($resolved-eq[IO.Path]::GetPathRoot($resolved).TrimEnd('\')-or$resolved-eq$env:USERPROFILE-or$resolved-eq$env:windir-or$resolved-eq$env:ProgramFiles){throw 'Choose a dedicated application directory, not a system or profile root.'}
$check=$resolved
while($check){
    if((Test-Path -LiteralPath $check)-and((Get-Item -LiteralPath $check -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Installation paths must not contain junctions or symbolic links.'}
    $parent=Split-Path $check -Parent
    if($parent-eq$check){break};$check=$parent
}
$files=@('Start-ServerMaintenance.ps1','SqlExpress.Core.ps1','WindowsUpdate.Core.ps1','Maintenance.Core.ps1','Install-FromGitHub.ps1','README.md','SECURITY.md','LICENSE','VERSION')
$manifest=Join-Path $PSScriptRoot 'manifest.sha256'
if(-not(Test-Path $manifest)){throw 'Release manifest missing.'}
foreach($line in Get-Content $manifest){
    if($line-notmatch'^([A-Fa-f0-9]{64}) \*(.+)$'){throw 'Invalid manifest.'}
    $hash=$matches[1];$name=$matches[2]
    if($name-notin@($files+'Install.ps1'+'Install.cmd')){throw 'Unexpected manifest path.'}
    if((Get-FileHash (Join-Path $PSScriptRoot $name)).Hash-ne$hash){throw "Manifest mismatch: $name"}
}
New-Item -ItemType Directory -Path $Destination -Force|Out-Null
& icacls.exe $Destination /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'|Out-Null
if($LASTEXITCODE-ne0){throw 'Cannot protect program directory.'}
if([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')-ne[IO.Path]::GetFullPath($Destination).TrimEnd('\')){
    foreach($name in $files){Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $Destination $name) -Force}
}
New-Item -ItemType Directory -Path (Join-Path $Destination Runs),(Join-Path $Destination Packages) -Force|Out-Null
Write-Host "Installed to $Destination. Existing Runs and Packages preserved."
Write-Host "Run: & '$Destination\Start-ServerMaintenance.ps1'"
