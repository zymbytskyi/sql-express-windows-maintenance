#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('Menu','Check','Windows','Sql','All')][string]$Mode='Menu',
    [switch]$Confirm,[switch]$Resume,
    [ValidateSet('0','1')][string]$BackupChoice,
    [string]$LocalPackagePath,[string]$InstanceName,
    [string]$RunRoot=(Join-Path $PSScriptRoot 'Runs')
)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$runtimeBase=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Runs')).TrimEnd('\')
$runtimeTarget=[IO.Path]::GetFullPath($RunRoot).TrimEnd('\')
if($runtimeTarget-ne$runtimeBase-and-not$runtimeTarget.StartsWith($runtimeBase+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'RunRoot must be Runs or a subdirectory inside this installation.'}
$RunRoot=$runtimeTarget
. (Join-Path $PSScriptRoot 'SqlExpress.Core.ps1')
. (Join-Path $PSScriptRoot 'WindowsUpdate.Core.ps1')
. (Join-Path $PSScriptRoot 'Maintenance.Core.ps1')
$packageRoot=Join-Path $PSScriptRoot 'Packages'
$statePath=Join-Path $RunRoot 'current.json'
function Get-BootStamp {(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')}
function Test-PendingRestart {
    (New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}
function Save-PatchState {
    param($State)
    $State.UpdatedUtc=[datetime]::UtcNow.ToString('o')
    $temp=$statePath+'.tmp'
    [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    if(Test-Path $statePath){[IO.File]::Replace($temp,$statePath,[NullString]::Value)}else{[IO.File]::Move($temp,$statePath)}
}
function Assert-ExpressHost {
    if((Get-CimInstance Win32_OperatingSystem).ProductType-ne3){throw 'This package supports Windows Server member/standalone servers only, not clients or domain controllers.'}
    if(Test-Path 'HKLM:\Cluster'){throw 'Cluster membership is not supported.'}
    if(Get-Service ClusSvc -ErrorAction SilentlyContinue){throw 'Failover Cluster Service is present; standalone hosts only.'}
    $map=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    $registered=@($map.PSObject.Properties|Where-Object{$_.Name-notmatch'^PS'})
    $instances=@(Get-LocalExpressInstances)
    if(-not$instances.Count-or$instances.Count-ne$registered.Count){throw 'Every local SQL instance must be query-ready SQL Server 2019, 2022 or 2025 Express. See the per-instance diagnostics above; unsupported editions and inaccessible instances remain blocked.'}
    foreach($instance in $instances){
        if(-not$instance.IsSysadmin){throw "SQL sysadmin required: $($instance.DisplayName)"}
        $q="SELECT CAST(SERVERPROPERTY('IsClustered') AS int) C, CAST(SERVERPROPERTY('IsHadrEnabled') AS int) H, (SELECT COUNT(*) FROM sys.availability_replicas) R;"
        $r=(Invoke-SqlQuery $instance.ServerInstance $q).Rows[0]
        if($r.C-or$r.H-or$r.R){throw 'FCI/Always On/AG detected.'}
    }
    return $instances
}
function Request-PatchRestart {
    param($State,[string]$NextStage)
    $State.Stage='AwaitingRestart';$State.NextStage=$NextStage;$State.BootBefore=Get-BootStamp;Save-PatchState $State
    Write-Host 'Restart required. Saved state; run this same script after signing in. No scheduled task or automatic resume.' -ForegroundColor Yellow
    if(-not$Confirm-and(Test-Yes (Read-Host 'Restart now? [y/N]'))){
        & shutdown.exe /r /t 30 /d p:4:2 /c 'SQL Express and Windows maintenance'
        if($LASTEXITCODE-ne0){throw 'Restart request failed; restart manually.'}
    }
}
function Test-FinalHealth {
    param($State)
    foreach($instance in @(Assert-ExpressHost)){
        $q='SELECT name,state_desc,HAS_DBACCESS(name) AS HasAccess FROM sys.databases;'
        foreach($row in (Invoke-SqlQuery $instance.ServerInstance $q).Rows){if($row.state_desc-ne'ONLINE'-or$row.HasAccess-ne1){throw "Database not ready: $($instance.DisplayName)/$($row.name)"}}
        if($State.TargetVersion-and$instance.InstanceName-eq$State.Instance-and[version]$instance.Version-lt[version]$State.TargetVersion){throw 'SQL build is below the selected target.'}
        Write-Host "PASS: $($instance.DisplayName) $($instance.Version); all databases online and accessible." -ForegroundColor Green
    }
    $stopped=@(Get-CimInstance Win32_Service|Where-Object{$_.StartMode-eq'Auto'-and$_.State-ne'Running'})
    $sqlStopped=@($stopped|Where-Object{$_.Name-match'^(MSSQL|SQLAgent|SQLBrowser|SQLWriter|SQLTELEMETRY)'})
    if($sqlStopped.Count){throw ('Automatic SQL services stopped: '+($sqlStopped.Name-join', '))}
    if($stopped.Count){Write-Warning ('Other automatic services stopped (review): '+($stopped.Name-join', '))}
    if(Test-PendingRestart){throw 'A pending restart remains.'}
}
$mutex=New-Object Threading.Mutex($false,'Global\SqlExpressWindowsMaintenance')
$sqlMutex=New-Object Threading.Mutex($false,'Global\SqlPatchStandaloneInstall')
$sqlAcquired=$false
$acquired=$false;$transcript=$false;$state=$null
try{
    try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
    if(-not$acquired){throw 'Another maintenance session is active.'}
    try{$sqlAcquired=$sqlMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$sqlAcquired=$true}
    if(-not$sqlAcquired){throw 'Another SQL patch operation is active.'}
    $check=$RunRoot
    while($check-and$check.Length-ge$PSScriptRoot.Length){
        if((Test-Path -LiteralPath $check)-and((Get-Item -LiteralPath $check -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'Runtime paths must not contain junctions or symbolic links.'}
        $check=Split-Path $check -Parent
    }
    New-Item -ItemType Directory -Path $RunRoot -Force|Out-Null
    # Protect journals against non-administrator modification.
    & icacls.exe $RunRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if($LASTEXITCODE-ne0){throw 'Could not protect runtime directory.'}
    Start-Transcript -Path (Join-Path $RunRoot ('Session-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log'))|Out-Null;$transcript=$true
    $machine=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
    if(Test-Path $statePath){$state=Get-Content $statePath -Raw -Encoding UTF8|ConvertFrom-Json;if($state.PSObject.Properties.Name-notcontains'RestartRequired'){$state|Add-Member NoteProperty RestartRequired $false}}
    if($state-and$state.MachineId-ne$machine){throw 'State belongs to another Windows host.'}
    if($Mode-eq'Check'){
        $instances=@(Assert-ExpressHost)
        foreach($item in $instances){Write-Host "$($item.DisplayName) $($item.Version)";Show-BackupHistory $item.ServerInstance}
        Show-WindowsUpdateScan (Get-WindowsUpdateScan)
        Write-Host "Pending restart: $(Test-PendingRestart)";return
    }
    if($state-and$state.Stage-ne'Complete'){
        Write-Host "Saved maintenance: $($state.Mode), stage $($state.Stage), updated $($state.UpdatedUtc)"
        if(-not$Resume-and-not(Test-Yes (Read-Host 'Continue this saved run? [y/N]'))){return}
        $resolved=Resolve-SavedStage $state $machine (Get-BootStamp) (Test-PendingRestart)
        $Mode=$state.Mode;$InstanceName=$state.Instance
        if($state.Stage-eq'AwaitingRestart'){
            if($resolved-eq'AwaitingRestart'){Write-Host 'Restart has not completed; restart Windows, then run this script again.';return}
            Wait-AutomaticSqlServices
            $instances=@(Assert-ExpressHost)
            $state.Stage=$resolved;$state.RestartRequired=$false;Save-PatchState $state
        }
        $instances=@(Assert-ExpressHost)
    }else{
        $instances=@(Assert-ExpressHost)
        if($Mode-eq'Menu'){
            Write-Host "SQL EXPRESS + WINDOWS MAINTENANCE`n1. SQL Express only`n2. Windows Update only`n3. Windows Update + SQL Express`n0. Exit"
            switch(Read-Host 'Select'){'1'{$Mode='Sql'}'2'{$Mode='Windows'}'3'{$Mode='All'}'0'{return}default{throw 'Select 0-3.'}}
        }
        if(-not$InstanceName){$instance=Select-Instance;$InstanceName=$instance.InstanceName}
        if(-not@($instances|Where-Object InstanceName -eq $InstanceName).Count){throw 'Selected instance not found.'}
        if($state){Copy-Item $statePath (Join-Path $RunRoot ('Completed-'+[guid]::NewGuid().ToString('N')+'.json'))}
        $state=[pscustomobject]@{Schema=1;MachineId=$machine;Mode=$Mode;Instance=$InstanceName;Stage='Backups';NextStage='';BootBefore='';RestartRequired=$false;TargetVersion='';PackagePath='';PackageHash='';UpdatedUtc='';Updates=@();WindowsHistory=@()}
        Save-PatchState $state
    }
    if(Get-Process setup,msiexec -ErrorAction SilentlyContinue){throw 'Another Setup/MSI process is active. Review before maintenance.'}
    if($state.RestartRequired-or(Test-PendingRestart)){Request-PatchRestart $state $state.Stage;return}
    if($state.Stage-eq'Backups'){
        foreach($item in $instances){Show-BackupHistory $item.ServerInstance}
        if(-not$BackupChoice){$BackupChoice=Read-Host 'Create verified COPY_ONLY system backups on all local Express instances? 0 no, 1 yes [0]';if(-not$BackupChoice){$BackupChoice='0'}}
        if($BackupChoice-notin@('0','1')){throw 'Backup choice must be 0 or 1.'}
        if($BackupChoice-eq'1'){
            foreach($item in $instances){Invoke-SystemBackups $item}
        }
        $state.Stage=if($Mode-eq'Sql'){'Sql'}else{'WindowsScan'};Save-PatchState $state
    }
    if($state.Stage-in@('WindowsScan','DownloadingWindows')){
        for($pass=1;$pass-le3;$pass++){
            $scan=Get-WindowsUpdateScan;Show-WindowsUpdateScan $scan
            if(-not$scan.Updates.Count){$state.Stage=if($Mode-eq'All'){'Sql'}else{'Verify'};Save-PatchState $state;break}
            Write-Host 'Installing this list accepts the updates EULAs. Review vendor terms before confirming.'
            if(-not$Confirm-and(Read-Host 'Type 2 to download and install the listed Windows updates')-ne'2'){Write-Host 'Cancelled; no Windows update installation requested.';return}
            $restart=Install-WindowsUpdateBatch $scan $state
            if($restart-or(Test-PendingRestart)){Request-PatchRestart $state WindowsScan;return}
        }
        if($state.Stage-eq'WindowsScan'){Write-Host 'Three batches completed. Run again to rescan dependencies before continuing.';return}
    }
    for($sqlPass=0;$sqlPass-lt2-and$state.Stage-eq'Sql';$sqlPass++){
        $instance=@(Assert-ExpressHost|Where-Object InstanceName -eq $state.Instance)[0]
        if(-not$instance){throw 'Saved SQL instance is no longer available.'}
        $major=([version]$instance.Version).Major
        $latest=$null
        $package=$LocalPackagePath
        if(-not$package){
            $source=if($Confirm){'1'}else{Read-Host 'SQL update: 1 latest CU or security update (default), 2 local EXE'}
            if(-not$source-or$source-eq'1'){
                $latest=Get-LatestUpdate -Major $major -CurrentVersion $instance.Version
                Write-Host "Latest SQL target: $($latest.FinalName) | $($latest.FinalKB) | $($latest.FinalVersion) | released $($latest.FinalReleased)"
                if($latest.IsPrerequisite){Write-Host "Required first step: $($latest.Name) $($latest.KB) $($latest.Version). Security update follows after this CU; resume after any required restart." -ForegroundColor Yellow}
                $state.TargetVersion=$latest.Version
                if([version]$instance.Version-ge[version]$latest.Version){Write-Host 'SQL is already current; no installation.';$state.Stage='Verify';Save-PatchState $state}
                else{$package=Get-LatestPackage $latest}
            }elseif($source-eq'2'){$package=(Read-Host 'Full path to original Microsoft EXE').Trim('"')}else{throw 'Select 1 or 2.'}
        }
        if($state.Stage-eq'Sql'){
            Assert-SqlPackage $package -Major $major
            $version=(Get-Item $package).VersionInfo.ProductVersion
            if($latest-and[version]$version-ne[version]$latest.Version){throw 'Downloaded package version differs from the approved Microsoft CU metadata.'}
            $state.TargetVersion=[string]$version
            if([version]$instance.Version-ge[version]$version){Write-Host 'Selected build already installed; no downgrade.';$state.Stage='Verify';Save-PatchState $state}
            else{
                Write-Host "$($instance.DisplayName): $($instance.Version) -> $version"
                if(-not$Confirm-and-not(Test-Yes (Read-Host 'Accept SQL license terms and install? [y/N]'))){return}
                $state.PackagePath=[IO.Path]::GetFullPath($package);$state.PackageHash=(Get-FileHash $package).Hash;$state.Stage='InstallingSql';Save-PatchState $state
                $code=Invoke-QuietSqlSetup $package $instance.InstanceName -Major $major
                $next=if($latest-and$latest.IsPrerequisite){'Sql'}else{'Verify'}
                $state.RestartRequired=($code-eq3010);$state.Stage=$next;Save-PatchState $state
                if($code-eq3010-or(Test-PendingRestart)){Request-PatchRestart $state $next;return}
                if($next-eq'Sql'){
                    Wait-AutomaticSqlServices
                    $fresh=@(Assert-ExpressHost|Where-Object InstanceName -eq $state.Instance)
                    if($fresh.Count-ne1-or[version]$fresh[0].Version-lt[version]$version){throw 'Prerequisite CU build verification failed; security installation was not started.'}
                }
            }
        }
    }
    if($state.Stage-eq'Sql'){Write-Host 'SQL maintenance is not complete. Run again to continue to the latest security target.';return}
    if($state.Stage-eq'Verify'){
        Test-FinalHealth $state;Start-Sleep -Seconds 3;Test-FinalHealth $state
        $state.Stage='Complete';Save-PatchState $state
        Write-Host 'COMPLETE: selected maintenance phases and final checks passed.' -ForegroundColor Green
    }
}catch{Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{if($transcript){Stop-Transcript|Out-Null};if($sqlAcquired){$sqlMutex.ReleaseMutex()};$sqlMutex.Dispose();if($acquired){$mutex.ReleaseMutex()};$mutex.Dispose()}
