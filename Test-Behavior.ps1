#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot WindowsUpdate.Core.ps1)
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
function New-Update {
    [pscustomobject]@{Title='Security update';Type=1;BrowseOnly=$false;Categories=@();InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$false};IsDownloaded=$true;MaxDownloadSize=1MB;EulaAccepted=$true;Identity=[pscustomobject]@{UpdateID='ID';RevisionNumber=1}}
}
$u=New-Update;Assert ((Get-UpdateExclusion $u)-eq'') 'Security update excluded'
foreach($case in @('Driver','Optional','Preview','SQL','Upgrade','Interactive')){
    $u=New-Update
    switch($case){Driver{$u.Type=2}Optional{$u.BrowseOnly=$true}Preview{$u.Title='Preview update'}SQL{$u.Title='SQL Server CU'}Upgrade{$u.Categories=@([pscustomobject]@{CategoryID='3689BDC8-B205-4AF4-8D4A-A63924C5E9D5';Name='Upgrades'})}Interactive{$u.InstallationBehavior.CanRequestUserInput=$true}}
    Assert ([bool](Get-UpdateExclusion $u)) "Unsafe $case included"
}
function Save-PatchState {param($State);$script:stages.Add($State.Stage)}
function Get-CimInstance {param($ClassName,$Filter);[pscustomobject]@{FreeSpace=$script:free}}
function New-WuaCallback {New-Object object}
function Wait-WuaJob {param($Job,$Action,$Updates)}
$script:free=20GB;$script:downloadCode=2;$script:installCode=2;$script:starts=0
$download=[pscustomobject]@{Updates=$null}
$download|Add-Member ScriptMethod BeginDownload {param($a,$b,$c);return $null}
$download|Add-Member ScriptMethod EndDownload {param($j);[pscustomobject]@{ResultCode=$script:downloadCode}}
$installer=[pscustomobject]@{IsBusy=$false;RebootRequiredBeforeInstallation=$false;Updates=$null;ForceQuiet=$false;AllowSourcePrompts=$true}
$installer|Add-Member ScriptMethod BeginInstall {param($a,$b,$c);$script:starts++;return $null}
$installer|Add-Member ScriptMethod EndInstall {
    param($j)
    $r=[pscustomobject]@{ResultCode=$script:installCode;RebootRequired=$true}
    $r|Add-Member ScriptMethod GetUpdateResult {param($i);[pscustomobject]@{ResultCode=$script:installCode;HResult=0;RebootRequired=$true}}
    return $r
}
$session=New-Object object
$session|Add-Member ScriptMethod CreateUpdateInstaller {return $installer}
$session|Add-Member ScriptMethod CreateUpdateDownloader {return $download}
$scan=[pscustomobject]@{Session=$session;Updates=@((New-Update));Excluded=@()}
foreach($case in @('Success','PartialInstall','DownloadFailure','Disk','Busy')){
    $script:free=20GB;$script:downloadCode=2;$script:installCode=2;$script:starts=0;$installer.IsBusy=$false
    switch($case){PartialInstall{$script:installCode=3}DownloadFailure{$script:downloadCode=3}Disk{$script:free=1GB}Busy{$installer.IsBusy=$true}}
    $state=[pscustomobject]@{Stage='WindowsScan';RestartRequired=$false;Updates=@();WindowsHistory=@()};$script:stages=New-Object 'Collections.Generic.List[string]'
    $failed=$false;try{$restart=Install-WindowsUpdateBatch $scan $state}catch{$failed=$true}
    if($case-eq'Success'){Assert (-not$failed-and$restart-and$state.Stage-eq'WindowsScan') 'Success/reboot state incorrect'}
    else{Assert $failed "$case not blocked"}
    if($case-in@('DownloadFailure','Disk','Busy')){Assert ($script:starts-eq0) 'Installer started after failed prerequisites'}
    if($case-eq'PartialInstall'){Assert ($state.Stage-eq'WindowsFailed') 'Partial success falsely reported complete'}
}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot Start-ServerMaintenance.ps1),[ref]$tokens,[ref]$errors)
$node=$ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-eq'Request-PatchRestart'},$true)
Invoke-Expression $node.Extent.Text
function Get-BootStamp {'BOOT1'}
$Confirm=$true;$script:stages=New-Object 'Collections.Generic.List[string]'
function shutdown.exe {throw 'Unexpected automatic restart'}
$state=[pscustomobject]@{Stage='';NextStage='';BootBefore=''}
Request-PatchRestart $state WindowsScan
Assert ($state.Stage-eq'AwaitingRestart'-and$state.NextStage-eq'WindowsScan'-and$state.BootBefore-eq'BOOT1') 'Restart continuation was not persisted'
Write-Output 'PASS: exclusions, successful batch, partial failure, failed download, disk/busy gates, persisted manual reboot without automatic restart.'
. (Join-Path $PSScriptRoot Maintenance.Core.ps1)
$state=[pscustomobject]@{Schema=1;MachineId='HOST';Mode='All';Stage='AwaitingRestart';BootBefore='BOOT1';NextStage='WindowsScan'}
Assert ((Resolve-SavedStage $state HOST BOOT1 $false)-eq'AwaitingRestart') 'Unchanged boot accepted'
Assert ((Resolve-SavedStage $state HOST BOOT2 $true)-eq'AwaitingRestart') 'Pending restart ignored'
Assert ((Resolve-SavedStage $state HOST BOOT2 $false)-eq'WindowsScan') 'Resume did not return to Windows rescan'
foreach($stage in @('InstallingSql','InstallingWindows','WindowsFailed','Unknown')){
    $state.Stage=$stage;$blocked=$false;try{Resolve-SavedStage $state HOST BOOT2 $false}catch{$blocked=$true};Assert $blocked "Unsafe resume $stage"
}
$state.Stage='Sql';$blocked=$false;try{Resolve-SavedStage $state OTHER BOOT2 $false}catch{$blocked=$true};Assert $blocked 'Foreign machine journal accepted'
Write-Output 'PASS: changed-boot continuation, pending-restart gate, unknown installation outcome and foreign-host rejection.'
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
    Assert ($WindowStyle-eq'Hidden') 'SQL console was not hidden'
    foreach($arg in @('/quiet','/hideconsole','/action=patch','/instancename=SQLEXPRESS','/IAcceptSQLServerLicenseTerms')){Assert ($ArgumentList-contains$arg) "Missing Setup argument $arg"}
    $p=[pscustomobject]@{Handle=1;ExitCode=$script:exitCode}
    $p|Add-Member ScriptMethod WaitForExit {param($ms);return $true}
    $p|Add-Member ScriptMethod Refresh {}
    $p|Add-Member ScriptMethod Dispose {}
    return $p
}
foreach($code in @(0,3010,1603)){
    $script:exitCode=$code;$blocked=$false
    try{$actual=Invoke-QuietSqlSetup 'fixture.exe' SQLEXPRESS}catch{$blocked=$true}
    if($code-eq1603){Assert $blocked 'Failed SQL Setup accepted'}else{Assert (-not$blocked-and$actual-eq$code) 'Successful SQL result lost'}
}
Write-Output 'PASS: quiet SQL Setup argument contract, hidden window, success/reboot codes and failure rejection (mocked installer).'
$script:serviceProbes=0
function Get-CimInstance {param($ClassName);$script:serviceProbes++;[pscustomobject]@{Name='MSSQL$SQLEXPRESS';StartMode='Auto';State=if($script:serviceProbes-lt3){'Stopped'}else{'Running'}}}
function Start-Sleep {param($Seconds)}
Wait-AutomaticSqlServices -TimeoutSeconds 10
Assert ($script:serviceProbes-eq3) 'Delayed automatic SQL start was not awaited'
Write-Output 'PASS: delayed automatic SQL startup is awaited without starting services manually.'
