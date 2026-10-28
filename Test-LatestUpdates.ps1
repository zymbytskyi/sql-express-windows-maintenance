#Requires -Version 5.1
param([switch]$Live)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot SqlExpress.Core.ps1)
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
if($Live){
    foreach($major in @(15,16,17)){
        $u=Get-LatestUpdate $major ([version]"$major.0.1000.1")
        Write-Output "PASS live RTM plan: $major -> $($u.Name) -> $($u.FinalName) $($u.FinalKB) $($u.FinalVersion) $($u.FinalReleased)"
        if($u.IsPrerequisite){
            $s=Get-LatestUpdate $major ([version]$u.Version)
            Assert (-not$s.IsPrerequisite-and$s.Version-eq$u.FinalVersion) 'Security continuation did not reach the target'
            Write-Output "PASS live security media: $($s.KB) $($s.Version), Catalog SHA-256 $($s.Sha256)"
        }
    }
    return
}
$html=@'
<tr><td>15.0.4500.2</td><td>None</td><td>CU32 + GDR</td><td><a>KB5128494</a></td><td>October 13, 2026</td></tr>
<tr><td>15.0.4430.1</td><td>None</td><td>CU32</td><td>KB5054833</td><td>February 27, 2025</td></tr>
<tr><td>15.0.2200.2</td><td>None</td><td>GDR</td><td>KB5128493</td><td>October 14, 2026</td></tr>
<tr><td>16.0.4305.5</td><td>None</td><td>CU27 + GDR</td><td>KB5126934</td><td>October 13, 2026</td></tr>
'@
$history=@(Convert-SqlHistory $html 15)
Assert ($history.Count-eq2) 'RTM GDR or another major leaked into CU branch'
$p=Select-SqlUpdateStep $history ([version]'15.0.1000.1')
Assert ($p.IsPrerequisite-and$p.Step.Name-eq'CU32'-and$p.Target.Name-eq'CU32 + GDR') 'Missing base CU prerequisite'
foreach($v in @('15.0.4430.1','15.0.4490.1','15.0.4500.2','15.0.9999.1')){
    $p=Select-SqlUpdateStep $history ([version]$v)
    Assert (-not$p.IsPrerequisite-and$p.Step.Version-eq'15.0.4500.2') 'Wrong security selection or attempted base downgrade'
}
$newCu=[pscustomobject]@{Name='CU33';Version='15.0.4600.1';KB='KB9999999';Released='2026-10-22'}
$p=Select-SqlUpdateStep @($history+$newCu) ([version]'15.0.4430.1')
Assert ($p.Step.Name-eq'CU33'-and-not$p.IsPrerequisite) 'Newer CU did not supersede older security update'
$blocked=$false;try{Select-SqlUpdateStep @($history[0]) ([version]'15.0.1000.1')}catch{$blocked=$true};Assert $blocked 'Missing prerequisite accepted'
$blocked=$false;try{Select-SqlUpdateStep @() ([version]'15.0.1000.1')}catch{$blocked=$true};Assert $blocked 'Empty metadata accepted'

$script:badHost=$false;$script:missingDigest=$false;$script:ambiguous=$false
function Invoke-WebRequest {
    param($Uri,$Method,$Body,[switch]$UseBasicParsing,$TimeoutSec)
    if($Uri-match'Search.aspx'){
        $text="00000000-0000-0000-0000-000000000001_link'>Security Update for SQL Server 2019 RTM CU (KB5128494)</a>"
        if($script:ambiguous){$text+="00000000-0000-0000-0000-000000000002_link'>Security Update for SQL Server 2019 RTM CU (KB5128494)</a>"}
        return [pscustomobject]@{Content=$text}
    }
    Assert ($Method-eq'Post'-and$Body.updateIDs-match'00000000-0000-0000-0000-000000000001') 'Catalog request incorrect'
    $hostName=if($script:badHost){'example.org'}else{'catalog.s.download.windowsupdate.com'}
    $digest=[Convert]::ToBase64String((New-Object byte[] 32))
    $text="downloadInformation[0].files[0].url = 'https://$hostName/test/sqlserver2019-kb5128494-x64_123abc.exe';"
    if(-not$script:missingDigest){$text+="downloadInformation[0].files[0].sha256 = '$digest';"}
    [pscustomobject]@{Content=$text}
}
$media=Get-CatalogSqlMedia $history[0] 15
Assert ($media.Sha256.Length-eq64-and$media.FileName-eq'SQLServer2019-KB5128494-x64.exe') 'Catalog hash/filename mapping failed'
foreach($case in @('badHost','missingDigest','ambiguous')){
    Set-Variable -Name $case -Scope Script -Value $true
    $blocked=$false;try{Get-CatalogSqlMedia $history[0] 15}catch{$blocked=$true};Assert $blocked "Unsafe Catalog $case accepted"
    Set-Variable -Name $case -Scope Script -Value $false
}
Write-Output 'PASS: CU/security selection, prerequisite planning, newer CU supersedence, no RTM GDR/major mixing, missing metadata, Catalog host/hash/ambiguity gates.'

# Execute the actual SQL orchestration loop with mocked installers, never Setup.
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot Start-ServerMaintenance.ps1),[ref]$t,[ref]$e)
$loop=$ast.Find({param($n)$n-is[Management.Automation.Language.ForStatementAst]-and$n.Extent.Text.StartsWith('for($sqlPass=')},$true)
Assert ($null-ne$loop) 'SQL orchestration loop missing'
function Assert-ExpressHost {[pscustomobject]@{InstanceName='TEST';DisplayName='TEST';Version=$script:installed}}
function Get-LatestUpdate {
    param($Major,$CurrentVersion)
    $plan=Select-SqlUpdateStep $history ([version]$CurrentVersion)
    $script:stepVersion=$plan.Step.Version
    [pscustomobject]@{Name=$plan.Step.Name;KB=$plan.Step.KB;Version=$plan.Step.Version;Released=$plan.Step.Released;IsPrerequisite=$plan.IsPrerequisite;FinalName=$plan.Target.Name;FinalKB=$plan.Target.KB;FinalVersion=$plan.Target.Version;FinalReleased=$plan.Target.Released}
}
function Get-LatestPackage {param($Update);return 'fixture.exe'}
function Assert-SqlPackage {param($Path,$Major)}
function Get-Item {param($Path);[pscustomobject]@{VersionInfo=[pscustomobject]@{ProductVersion=$script:stepVersion}}}
function Get-FileHash {param($Path);[pscustomobject]@{Hash='FIXTURE'}}
function Save-PatchState {param($State)}
function Invoke-QuietSqlSetup {param($Package,$InstanceName,$Major);$script:installs++;$script:installed=$script:stepVersion;return $script:setupCode}
function Test-PendingRestart {return $false}
function Wait-AutomaticSqlServices {}
function Request-PatchRestart {param($State,$NextStage);$State.Stage='AwaitingRestart';$State.NextStage=$NextStage}
$Confirm=$true;$LocalPackagePath=$null
foreach($code in @(0,3010)){
    $script:installed='15.0.1000.1';$script:installs=0;$script:setupCode=$code
    $state=[pscustomobject]@{Stage='Sql';Instance='TEST';TargetVersion='';PackagePath='';PackageHash='';RestartRequired=$false;NextStage=''}
    & ([scriptblock]::Create($loop.Extent.Text))
    if($code-eq0){Assert ($script:installs-eq2-and$state.Stage-eq'Verify'-and$script:installed-eq'15.0.4500.2') 'CU + security did not complete sequentially'}
    else{Assert ($script:installs-eq1-and$state.Stage-eq'AwaitingRestart'-and$state.NextStage-eq'Sql') 'Prerequisite restart incorrectly skipped security continuation'}
}
Write-Output 'PASS: actual SQL loop installs CU then security, or persists Sql continuation when prerequisite requests reboot (mocked Setup).'
