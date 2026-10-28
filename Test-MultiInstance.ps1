#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
Import-Module Microsoft.PowerShell.Utility
. (Join-Path $PSScriptRoot Maintenance.Core.ps1)
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot Start-ServerMaintenance.ps1),[ref]$t,[ref]$e)
$loop=$ast.Find({param($n)$n-is[Management.Automation.Language.WhileStatementAst]-and$n.Extent.Text.StartsWith('while($true)')},$true)
Assert ($null-ne$loop) 'Multi-instance orchestration missing'
function Assert-ExpressHost {
    foreach($name in 'A','B'){[pscustomobject]@{InstanceName=$name;DisplayName=$name;Version=$script:builds[$name]}}
}
function Confirm-BackupReadiness {param($Instances,$MaxAgeDays,[switch]$AcceptRisk,[switch]$Unattended)}
function Get-LatestUpdate {
    param($Major,$CurrentVersion)
    $script:target=if($Major-eq14){'14.0.3560.2'}else{'17.0.5035.5'}
    [pscustomobject]@{FinalName='Latest';FinalKB='KBfixture';FinalVersion=$script:target;FinalReleased='2026-10-13';Version=$script:target}
}
function Get-LatestPackage {param($Update);return 'fixture.exe'}
function Assert-SqlPackage {param($Path,$Major)}
function Get-Item {param($Path);[pscustomobject]@{VersionInfo=[pscustomobject]@{ProductVersion=$script:target}}}
function Get-FileHash {param($Path);[pscustomobject]@{Hash='FIXTURE'}}
function Save-PatchState {param($State)}
function Invoke-QuietSqlSetup {
    param($Package,$InstanceName,$Major)
    $script:calls.Add($InstanceName)
    if($script:scenario-eq'FailSecond'-and$InstanceName-eq'B'){throw 'Setup failed fixture'}
    $script:builds[$InstanceName]=$script:target
    if($script:scenario-eq'RebootFirst'-and$InstanceName-eq'A'){return 3010}
    return 0
}
function Test-PendingRestart {return $false}
function Request-PatchRestart {param($State,$NextStage);$State.NextStage=$NextStage;$State.Stage='AwaitingRestart'}
function Start-Sleep {param($Seconds)}
function Test-FinalHealth {
    param($State)
    Assert ([version]$script:builds[$State.Instance]-ge[version]$State.TargetVersion) 'Unverified instance advanced'
}
$Confirm=$true;$LocalPackagePath=$null;$BackupMaxAgeDays=7;$AcceptBackupRisk=$false
foreach($scenario in @('Success','RebootFirst','FailSecond')){
    $script:scenario=$scenario;$script:builds=@{A='14.0.1000.1';B='17.0.5015.4'};$script:calls=New-Object 'Collections.Generic.List[string]'
    $state=[pscustomobject]@{Mode='All';Stage='Sql';Instance='A';SqlQueue=@('A','B');CompletedSql=@();TargetVersion='';PackagePath='';PackageHash='';RestartRequired=$false;NextStage=''}
    $failed=$false;try{& ([scriptblock]::Create($loop.Extent.Text))}catch{$failed=$true;if($scenario-ne'FailSecond'){throw}}
    if($scenario-eq'FailSecond'){
        Assert ($failed-and$state.Stage-eq'InstallingSql'-and$state.CompletedSql.Count-eq1) 'Failed second instance falsely completed'
    }else{
        Assert (-not$failed) 'Unexpected orchestration failure'
        if($scenario-eq'RebootFirst'){
            Assert ($state.Stage-eq'AwaitingRestart'-and$state.NextStage-eq'Verify'-and$script:calls.Count-eq1) 'Second instance ran before restart'
            $state.Stage=$state.NextStage;$state.RestartRequired=$false
            & ([scriptblock]::Create($loop.Extent.Text))
        }
        Assert ($state.Stage-eq'Complete'-and$state.CompletedSql.Count-eq2) 'Multi-instance run incomplete'
    }
    Assert (($script:calls -join ',')-eq'A,B') 'Instance repeated or executed out of order'
}
Write-Output 'PASS: actual multi-instance orchestration, mixed majors, restart verification before next instance, no repeated Setup, fail-closed second installer outcome.'
