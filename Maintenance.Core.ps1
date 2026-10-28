function Invoke-SystemBackups {
    param($Instance)
    $root=[string](Invoke-SqlQuery $Instance.ServerInstance "SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(4000)) AS P;").Rows[0].P
    if(-not$root-or-not(Test-Path $root -PathType Container)){throw 'SQL default backup directory is unavailable.'}
    foreach($name in @('master','model','msdb')){
        $file=Join-Path $root ($Instance.InstanceName+'_'+$name+'_COPY_ONLY_'+[guid]::NewGuid().ToString('N')+'.bak')
        Write-Host "System backup: $name -> $file"
        $sql='BACKUP DATABASE {0} TO DISK={1} WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK={1} WITH CHECKSUM;' -f (Quote-SqlIdentifier $name),(Quote-SqlLiteral $file)
        [void](Invoke-SqlQuery $Instance.ServerInstance $sql -TimeoutSeconds 3600)
        Write-Host "Verified: $file" -ForegroundColor Green
    }
}
function Resolve-SavedStage {
    param($State,[string]$MachineId,[string]$BootStamp,[bool]$PendingRestart)
    if($State.Schema-ne1-or$State.MachineId-ne$MachineId){throw 'Unsupported journal or journal from another Windows host.'}
    if($State.Mode-notin@('Windows','Sql','All')){throw 'Invalid saved maintenance mode.'}
    if($State.Stage-in@('InstallingWindows','InstallingSql','WindowsFailed')){throw 'Previous installation requires manual review; no automatic retry.'}
    if($State.Stage-notin@('Backups','DownloadingWindows','WindowsScan','Sql','Verify','AwaitingRestart','Complete')){throw 'Unknown saved stage; manual review required.'}
    if($State.Stage-eq'AwaitingRestart'){
        if($BootStamp-eq$State.BootBefore-or$PendingRestart){return 'AwaitingRestart'}
        if($State.NextStage-notin@('Backups','DownloadingWindows','WindowsScan','Sql','Verify')){throw 'Invalid restart continuation.'}
        return $State.NextStage
    }
    return $State.Stage
}
function Wait-AutomaticSqlServices {
    param([int]$TimeoutSeconds=360)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do{
        $pending=@(Get-CimInstance Win32_Service|Where-Object{$_.StartMode-eq'Auto'-and$_.Name-match'^(MSSQL|SQLAgent|SQLBrowser|SQLWriter|SQLTELEMETRY)'-and$_.State-ne'Running'})
        if(-not$pending.Count){return}
        Write-Host ("Waiting for automatic/delayed SQL services: {0}; elapsed {1:n0}s. No services are started manually."-f($pending.Name-join', '),$timer.Elapsed.TotalSeconds)
        Start-Sleep -Seconds 5
    }while($timer.Elapsed.TotalSeconds-lt$TimeoutSeconds)
    throw ('SQL service startup timeout: '+($pending.Name-join', ')+'. Review Windows service events; saved continuation was retained.')
}
function Assert-SqlPackage {
    param([string]$Path,[Parameter(Mandatory)][int]$Major)
    $release=Get-SqlRelease $Major
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'SQL update file not found.'}
    if([IO.Path]::GetFileName($Path)-notmatch('^SQLServer{0}-KB\d+-x64\.exe$'-f$release.Year)){throw "Expected original SQL Server $($release.Year) update media for this instance."}
    $sig=Get-AuthenticodeSignature -LiteralPath $Path
    if($sig.Status-ne'Valid'-or-not$sig.SignerCertificate-or$sig.SignerCertificate.Subject-notmatch'Microsoft Corporation'){throw 'Microsoft signature validation failed.'}
    if(([version](Get-Item $Path).VersionInfo.ProductVersion).Major-ne$Major){throw 'SQL package major version does not match the target instance.'}
}
function Invoke-QuietSqlSetup {
    param([string]$Package,[string]$InstanceName,[ValidateSet(15,16,17)][int]$Major=16)
    $arguments=@('/quiet','/hideconsole','/action=patch',"/instancename=$InstanceName",'/IAcceptSQLServerLicenseTerms')
    $process=Start-Process -FilePath $Package -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try{
        $null=$process.Handle;$timer=[Diagnostics.Stopwatch]::StartNew()
        while(-not$process.WaitForExit(5000)){Write-Host ("SQL Setup running; elapsed {0:n0}s. Logs: {1}\Microsoft SQL Server\{2}0\Setup Bootstrap\Log"-f$timer.Elapsed.TotalSeconds,$env:ProgramFiles,$Major)}
        $process.Refresh();$code=$process.ExitCode
        if($null-eq$code-or$code-notin@(0,3010)){throw "SQL Setup exit $code. Review Setup logs; no automatic retry."}
        return [int]$code
    }finally{$process.Dispose()}
}
function Assert-LatestExpressCu {
    param($Update,[Parameter(Mandatory)][int]$Major)
    $release=Get-SqlRelease $Major
    $url='https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-'+$release.Year+'/build-versions'
    try { $html=(Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 60).Content }
    catch {
        $kb=switch($Major){15{'kb4518398'}16{'kb5023451'}17{'kb5005684'}}
        $fallback='https://support.microsoft.com/en-us/servicing/sql/sql-server-'+$release.Year+'/'+$kb+'-build-versions'
        $html=(Invoke-WebRequest $fallback -UseBasicParsing -TimeoutSec 60).Content
    }
    foreach($row in [regex]::Matches($html,'<tr[^>]*>[\s\S]*?</tr>','IgnoreCase')){
        $text=[regex]::Replace([Net.WebUtility]::HtmlDecode([regex]::Replace($row.Value,'<[^>]+>',' ')),'\s+',' ').Trim()
        $match=[regex]::Match($text,"^CU\d+\s+\(Latest\)\s+($Major\.0\.\d+\.\d+)\b.*?\b(KB\d+)\b",'IgnoreCase')
        if($match.Success){
            if([version]$Update.Version-ne[version]$match.Groups[1].Value-or$Update.KB-ne$match.Groups[2].Value){throw 'Microsoft sources disagree on the latest CU. Use reviewed local media or retry later.'}
            return
        }
    }
    throw 'Latest CU could not be independently verified against Microsoft build history.'
}
