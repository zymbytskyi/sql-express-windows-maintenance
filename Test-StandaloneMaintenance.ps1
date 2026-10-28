#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot SqlExpress.Core.ps1)
. (Join-Path $PSScriptRoot Maintenance.Core.ps1)
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
Assert ((Get-BackupStatus ([DBNull]::Value) ([DBNull]::Value) 7)-eq'MISSING') 'Missing backup not highlighted'
Assert ((Get-BackupStatus (Get-Date) 169 7)-eq'OLD') 'Old backup not highlighted'
Assert ((Get-BackupStatus (Get-Date) 168 7)-eq'RECENT HISTORY') 'Weekly backup incorrectly old'
Assert ((Get-BackupStatus (Get-Date) -1 7)-eq'UNKNOWN AGE') 'Clock inconsistency not warned'
Assert ((Get-BackupStatus (Get-Date) 169 14)-eq'RECENT HISTORY') 'Custom backup threshold ignored'
function Show-BackupHistory {param($ServerInstance,$MaxAgeDays,[switch]$ReturnRisks);if($script:risk){'TEST/userdb: MISSING'}}
function Read-Host {param($Prompt);return $script:answer}
$script:risk=$true;$script:answer='no';$items=@([pscustomobject]@{ServerInstance='TEST'})
foreach($unattended in @($false,$true)){
    $blocked=$false;try{Confirm-BackupReadiness $items -Unattended:$unattended}catch{$blocked=$true};Assert $blocked 'Backup risk silently accepted'
}
$script:answer='YES';Confirm-BackupReadiness $items
Confirm-BackupReadiness $items -Unattended -AcceptRisk
$script:risk=$false;Confirm-BackupReadiness $items -Unattended
Write-Output 'PASS: missing/old/unknown backup warnings, weekly/custom threshold, decline and explicit interactive/unattended override.'

$instances=@([pscustomobject]@{InstanceName='A'},[pscustomobject]@{InstanceName='B'})
$state=[pscustomobject]@{Instance='A';TargetVersion='16.0.4305.5';PackagePath='';PackageHash='';Stage='Verify';SqlQueue=@('A','B');CompletedSql=@()}
Initialize-SqlQueue $state $instances
Complete-SqlQueueItem $state
Assert ($state.Instance-eq'B'-and$state.Stage-eq'Sql'-and$state.CompletedSql.Count-eq1) 'Queue did not advance after verified first instance'
$state.TargetVersion='17.0.5035.5';$state.Stage='Verify'
Complete-SqlQueueItem $state
Assert ($state.Stage-eq'Complete'-and$state.CompletedSql.Count-eq2) 'Queue falsely incomplete/complete'
$old=[pscustomobject]@{Instance='B'};Initialize-SqlQueue $old $instances
Assert ($old.SqlQueue.Count-eq1-and$old.SqlQueue[0]-eq'B') 'Old journal scope was widened'
$blocked=$false;try{Initialize-SqlQueue $state @($instances[0])}catch{$blocked=$true};Assert $blocked 'Missing saved instance accepted'
Write-Output 'PASS: multi-instance queue, per-instance completion/builds, old journal scope preservation, missing-instance gate.'

function Test-Path {param($LiteralPath,$Path,$PathType);return $true}
function Get-ItemProperty {param($LiteralPath);[pscustomobject]@{MSSQLSERVER='ID'}}
function Invoke-SqlQuery {
    param($ServerInstance,$Query,$TimeoutSeconds)
    [pscustomobject]@{Rows=@([pscustomobject]@{Edition=$script:edition;EngineEdition=$script:engine;ProductVersion=$script:version;ProductUpdateLevel='';IsSysadmin=1})}
}
foreach($major in @(14,15,16,17)){
    foreach($edition in @('Express Edition','Standard Edition','Enterprise Edition','Developer Edition','Standard Developer Edition','Enterprise Developer Edition','Enterprise Evaluation Edition','Web Edition')){
        $script:edition=$edition;$script:version="$major.0.1000.1";$script:engine=if($edition-match'Express'){4}elseif($edition-match'Standard|Web'){2}else{3}
        Assert (@(Get-LocalExpressInstances).Count-eq1) "Edition rejected: $edition on $major"
    }
}
$script:engine=8
Assert (@(Get-LocalExpressInstances).Count-eq0) 'Managed instance engine accepted as local standalone'
Write-Output 'PASS: all supported local editions on four SQL majors; managed/cloud engine excluded.'

# Test actual host safety gate with read-only mocks.
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot Start-ServerMaintenance.ps1),[ref]$t,[ref]$e)
$gate=$ast.Find({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-eq'Assert-ExpressHost'},$true)
Invoke-Expression $gate.Extent.Text
function Get-CimInstance {param($ClassName);[pscustomobject]@{ProductType=3}}
function Test-Path {param($Path);return $script:cluster}
function Get-Service {param($Name,$ErrorAction);if($script:clusterService){[pscustomobject]@{Name='ClusSvc'}}}
function Get-LocalExpressInstances {[pscustomobject]@{InstanceName='MSSQLSERVER';DisplayName='TEST';ServerInstance='TEST';IsSysadmin=$script:sysadmin}}
function Invoke-SqlQuery {param($ServerInstance,$Query);[pscustomobject]@{Rows=@([pscustomobject]@{C=$script:fci;H=$script:hadr;R=$script:replicas})}}
$script:cluster=$false;$script:clusterService=$false;$script:sysadmin=$true;$script:fci=0;$script:hadr=0;$script:replicas=0
Assert (@(Assert-ExpressHost).Count-eq1) 'Healthy standalone blocked'
foreach($case in @('cluster','clusterService','fci','hadr','replicas','sysadmin')){
    Set-Variable -Scope Script -Name $case -Value $(if($case-eq'sysadmin'){$false}else{1})
    $blocked=$false;try{Assert-ExpressHost}catch{$blocked=$true};Assert $blocked "Safety gate failed: $case"
    Set-Variable -Scope Script -Name $case -Value $(if($case-eq'sysadmin'){$true}else{0})
}
Write-Output 'PASS: WSFC/FCI/Always On/replica and missing-sysadmin safeguards retained.'

$script:backupCalls=New-Object 'Collections.Generic.List[string]'
function Test-Path {param($Path,$PathType);return $true}
function Invoke-SqlQuery {
    param($ServerInstance,$Query,$TimeoutSeconds)
    $script:backupCalls.Add($Query)
    if($Query-match'InstanceDefaultBackupPath'){return [pscustomobject]@{Rows=@([pscustomobject]@{P=[DBNull]::Value})}}
    if($Query-match'xp_instance_regread'){return [pscustomobject]@{Rows=@([pscustomobject]@{P='C:\Backups'})}}
    Assert ($Query-match'WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY'-and$TimeoutSeconds-eq3600) 'Backup/verification safety contract missing'
}
Invoke-SystemBackups ([pscustomobject]@{ServerInstance='TEST';InstanceName='TEST'})
Assert ($script:backupCalls.Count-eq5) '2017 registry fallback or system backup count incorrect'
foreach($db in @('master','model','msdb')){Assert (@($script:backupCalls|Where-Object{$_-match('BACKUP DATABASE \['+$db+'\]')}).Count-eq1) "Missing $db backup"}
Write-Output 'PASS: SQL 2017 default-backup-directory fallback; only master/model/msdb with COPY_ONLY,CHECKSUM and VERIFYONLY (mocked SQL).'
