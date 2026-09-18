#Requires -Version 5.1
$ErrorActionPreference='Stop'
$files=Get-ChildItem $PSScriptRoot -Filter *.ps1
foreach($file in $files){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e);if($e){throw "$($file.Name): $($e.Message)"}}
$main=(Get-Content (Join-Path $PSScriptRoot Start-ServerMaintenance.ps1) -Raw)+(Get-Content (Join-Path $PSScriptRoot Maintenance.Core.ps1) -Raw)
foreach($token in @('AwaitingRestart','BootBefore','MachineId','InstallingSql','InstallingWindows','WindowsFailed','Global\SqlExpressWindowsMaintenance','Global\SqlPatchStandaloneInstall','/hideconsole','-WindowStyle Hidden','Test-FinalHealth')){if(-not$main.Contains($token)){throw "Missing safety contract $token"}}
$wu=Get-Content (Join-Path $PSScriptRoot WindowsUpdate.Core.ps1) -Raw
foreach($token in @('BrowseOnly','SQL Server','CanRequestUserInput','ResultCode-ne2','AcceptEula','ForceQuiet','AllowSourcePrompts','Save-PatchState')){if(-not$wu.Contains($token)){throw "Missing WUA contract $token"}}
foreach($file in $files|Where-Object Name -ne 'Test-Package.ps1'){
    $text=Get-Content $file.FullName -Raw
    if($text-match'(?i)SQLEXPRESS01|SQLAGLAB|C:\\AI\\|github_pat_|ghp_[A-Za-z0-9]{20}|BEGIN .*PRIVATE KEY'){throw "Private data in $($file.Name)"}
    if($text-match'Register-ScheduledTask|Set-MpPreference|Add-MpPreference|AddService2|ServerSelection\s*='){throw "Disallowed policy mutation in $($file.Name)"}
}
Write-Output 'PASS: PowerShell syntax, state/safety contracts, update policy preservation, publication privacy.'
