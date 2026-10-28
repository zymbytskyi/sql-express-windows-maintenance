#Requires -Version 5.1
param([switch]$Live)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot SqlExpress.Core.ps1)
. (Join-Path $PSScriptRoot Maintenance.Core.ps1)
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
if($Live){
    foreach($major in @(15,16,17)){
        $update=Get-LatestCu -Major $major
        Assert-LatestExpressCu $update -Major $major
        Write-Output "PASS live Microsoft metadata: $major $($update.Name) $($update.KB) $($update.Version)"
    }
    return
}
function Invoke-WebRequest {
    param($Uri,[switch]$UseBasicParsing,$TimeoutSec)
    if($Uri-match'build-versions'){
        return [pscustomobject]@{Content="<tr><td>CU99 (Latest)</td><td>$script:major.0.9999.1</td><td>KB1234567</td></tr>"}
    }
    Assert ($Uri-match('id='+$script:release.DownloadId+'$')) 'Wrong download source'
    $file="SQLServer$($script:release.Year)-KB1234567-x64.exe"
    [pscustomobject]@{Content="Cumulative Update Package 99 for SQL Server $($script:release.Year) - KB1234567 Version: $script:major.0.9999.1 $file";Links=@([pscustomobject]@{href="https://download.microsoft.com/test/$file"},[pscustomobject]@{name='no href'})}
}
function Test-Path {param($LiteralPath,$PathType);return $true}
function Get-AuthenticodeSignature {param($LiteralPath);[pscustomobject]@{Status=$script:signature;SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Corporation'}}}
function Get-Item {param($Path);[pscustomobject]@{VersionInfo=[pscustomobject]@{ProductVersion=$script:mediaVersion}}}
foreach($script:major in @(15,16,17)){
    $script:release=Get-SqlRelease $major
    $update=Get-LatestCu -Major $major
    Assert-LatestExpressCu $update -Major $major
    $script:mediaVersion="$major.0.9999.1";$script:signature='Valid'
    Assert-SqlPackage $update.FileName -Major $major
    $script:mediaVersion='14.0.1000.1'
    $blocked=$false;try{Assert-SqlPackage $update.FileName -Major $major}catch{$blocked=$true};Assert $blocked 'Renamed wrong-major media accepted'
    $script:mediaVersion="$major.0.9999.1";$script:signature='HashMismatch'
    $blocked=$false;try{Assert-SqlPackage $update.FileName -Major $major}catch{$blocked=$true};Assert $blocked 'Invalid signature accepted'
    $script:signature='Valid'
    $blocked=$false;try{Assert-SqlPackage 'SQLServer2017-KB1234567-x64.exe' -Major $major}catch{$blocked=$true};Assert $blocked 'Wrong-year media accepted'
    $update.Version="$major.0.8888.1"
    $blocked=$false;try{Assert-LatestExpressCu $update -Major $major}catch{$blocked=$true};Assert $blocked 'Disagreeing Microsoft sources accepted'
}
$blocked=$false;try{Get-SqlRelease 14}catch{$blocked=$true};Assert $blocked 'Unsupported major accepted'
function Get-ItemProperty {param($LiteralPath);[pscustomobject]@{A='ID1';B='ID2';C='ID3';D='ID4';E='ID5'}}
function Invoke-SqlQuery {
    param($ServerInstance,$Query)
    $version=switch -Regex ($ServerInstance){'\\A$'{'15.0.1.1'}'\\B$'{'16.0.1.1'}'\\C$'{'17.0.1.1'}'\\D$'{'16.0.1.1'}default{throw 'Login failed fixture'}}
    $edition=if($ServerInstance-match'\\D$'){'Standard Edition'}else{'Express Edition'}
    [pscustomobject]@{Rows=@([pscustomobject]@{ProductVersion=$version;Edition=$edition;ProductUpdateLevel='';IsSysadmin=1})}
}
$instances=@(Get-LocalExpressInstances)
Assert ($instances.Count-eq3) 'Mixed-version Express discovery failed or unsupported host accepted'
Write-Output 'PASS: Express 2019/2022/2025 discovery, CU routing, source cross-check, wrong-major/wrong-year media, invalid signature, inaccessible and non-Express exclusion.'
