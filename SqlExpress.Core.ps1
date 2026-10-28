# Derived from sql-server-2022-express-self-patch v1.0.1 (MIT).
function Write-Step {
    param([string]$Text)
    Write-Host "`n== $Text ==" -ForegroundColor Cyan
}

function Invoke-SqlQuery {
    param([string]$ServerInstance, [string]$Query, [int]$TimeoutSeconds = 120)
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$ServerInstance;Database=master;Integrated Security=SSPI;Application Name=SimpleSqlPatch;Connect Timeout=15;Encrypt=False"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = $TimeoutSeconds
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return (, $table)
    }
    finally {
        if ($connection) { $connection.Dispose() }
    }
}

function Get-SqlRelease {
    param([Parameter(Mandatory)][int]$Major)
    switch ($Major) {
        15 { [pscustomobject]@{Year=2019; Major=15; DownloadId=100809} }
        16 { [pscustomobject]@{Year=2022; Major=16; DownloadId=105013} }
        17 { [pscustomobject]@{Year=2025; Major=17; DownloadId=108788} }
        default { throw "Unsupported SQL major version $Major. Supported Express releases: 2019, 2022, 2025." }
    }
}

function Get-LocalExpressInstances {
    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if (-not (Test-Path -LiteralPath $registryPath)) { throw 'No local SQL Server Database Engine instance was found.' }
    $map = Get-ItemProperty -LiteralPath $registryPath
    $instances = New-Object System.Collections.Generic.List[object]
    foreach ($property in $map.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
        $instanceName = [string]$property.Name
        $serverInstance = if ($instanceName -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$instanceName" }
        try {
            $query = @"
SELECT CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
       CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(32)) AS ProductVersion,
       CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(32)) AS ProductUpdateLevel,
       ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) AS IsSysadmin;
"@
            $row = (Invoke-SqlQuery -ServerInstance $serverInstance -Query $query).Rows[0]
            Write-Host "$serverInstance | $($row.Edition) | $($row.ProductVersion)"
            if (([version][string]$row.ProductVersion).Major -in @(15,16,17) -and [string]$row.Edition -match 'Express') {
                $instances.Add([pscustomobject]@{
                    InstanceName = $instanceName
                    ServerInstance = $serverInstance
                    DisplayName = if ($instanceName -eq 'MSSQLSERVER') { "$env:COMPUTERNAME (default)" } else { "$env:COMPUTERNAME\$instanceName" }
                    Edition = [string]$row.Edition
                    Version = [string]$row.ProductVersion
                    Update = [string]$row.ProductUpdateLevel
                    IsSysadmin = [bool]$row.IsSysadmin
                })
            } else { Write-Warning "$serverInstance is unsupported: $($row.Edition), $($row.ProductVersion). Expected Express 2019, 2022 or 2025." }
        }
        catch {
            Write-Warning "Could not query local instance '$serverInstance': $($_.Exception.Message)"
        }
    }
    return $instances.ToArray()
}

function Select-Instance {
    $instances = @(Get-LocalExpressInstances)
    if (-not $instances.Count) { throw 'No query-ready local SQL Server 2019/2022/2025 Express instance was found.' }
    if ($instances.Count -eq 1) {
        Write-Host "Found: $($instances[0].DisplayName) | $($instances[0].Edition) | $($instances[0].Version)"
        return $instances[0]
    }
    for ($index = 0; $index -lt $instances.Count; $index++) {
        Write-Host ("{0}. {1} | {2} | {3}" -f ($index + 1), $instances[$index].DisplayName, $instances[$index].Edition, $instances[$index].Version)
    }
    do { $choice = Read-Host 'Select local instance number' } until ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $instances.Count)
    return $instances[[int]$choice - 1]
}

function Show-BackupHistory {
    param([string]$ServerInstance)
    $query = @"
SELECT d.name AS DatabaseName,
       d.state_desc AS State,
       b.backup_finish_date AS LastFullBackup,
       b.is_copy_only AS IsCopyOnly,
       b.physical_device_name AS BackupPath
FROM sys.databases AS d
OUTER APPLY (
    SELECT TOP (1) bs.backup_finish_date, bs.is_copy_only, bmf.physical_device_name
    FROM msdb.dbo.backupset AS bs
    LEFT JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
    WHERE bs.database_name = d.name AND bs.type = 'D'
    ORDER BY bs.backup_finish_date DESC
) AS b
WHERE d.database_id <> 2
ORDER BY d.name;
"@
    $table = Invoke-SqlQuery -ServerInstance $ServerInstance -Query $query
    if (-not $table.Rows.Count) {
        Write-Host 'No user databases.'
        return
    }
    foreach ($row in $table.Rows) {
        $date = if ($row.LastFullBackup -eq [DBNull]::Value) { 'NEVER' } else { ([datetime]$row.LastFullBackup).ToString('yyyy-MM-dd HH:mm:ss') }
        $kind = if ($row.LastFullBackup -eq [DBNull]::Value) { '' } elseif ([bool]$row.IsCopyOnly) { 'COPY_ONLY' } else { 'FULL' }
        $path = if ($row.BackupPath -eq [DBNull]::Value) { '' } else { [string]$row.BackupPath }
        Write-Host ("{0} | {1} | last full: {2} {3}" -f $row.DatabaseName, $row.State, $date, $kind)
        if ($path) { Write-Host "  $path" -ForegroundColor DarkGray }
    }
    Write-Host 'The next step lets you optionally create new COPY_ONLY backups.' -ForegroundColor Yellow
}

function Quote-SqlIdentifier {
    param([string]$Value)
    return '[' + $Value.Replace(']', ']]') + ']'
}

function Quote-SqlLiteral {
    param([string]$Value)
    return "N'" + $Value.Replace("'", "''") + "'"
}

function Get-LatestCu {
    param([Parameter(Mandatory)][int]$Major)
    $release = Get-SqlRelease $Major
    $year = $release.Year
    $downloadPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=' + $release.DownloadId
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing -TimeoutSec 60
    $html = [Net.WebUtility]::HtmlDecode([string]$response.Content)
    $plain = [regex]::Replace($html, '<script[\s\S]*?</script>|<style[\s\S]*?</style>|<[^>]+>', ' ')
    $plain = [regex]::Replace($plain, '\s+', ' ')
    $fileMatch = [regex]::Match($plain, "SQLServer$year-KB\d+-x64\.exe", 'IgnoreCase')
    $versionMatch = [regex]::Match($plain, "Version:\s*($Major\.0\.\d+\.\d+)", 'IgnoreCase')
    $cuMatch = [regex]::Match($plain, "Cumulative Update Package\s+(\d+)\s+for SQL Server $year\s+-\s+(KB\d+)", 'IgnoreCase')
    $urls = @($response.Links | ForEach-Object {
        if ($_.PSObject.Properties.Name -contains 'href') { [string]$_.href }
    } | Where-Object { $_ -match "^https://download\.microsoft\.com/.*/SQLServer$year-KB\d+-x64\.exe(?:\?.*)?$" })
    if (-not $urls.Count) {
        $urlMatch = [regex]::Match($html, ('https://download\.microsoft\.com/[^"''\s<>]+/SQLServer{0}-KB\d+-x64\.exe(?:\?[^"''\s<>]*)?' -f $year), 'IgnoreCase')
        if ($urlMatch.Success) { $urls = @($urlMatch.Value) }
    }
    if (-not $fileMatch.Success -or -not $versionMatch.Success -or -not $cuMatch.Success -or -not $urls.Count) {
        throw "Could not read the current SQL Server $year CU from Microsoft Download Center. Choose option 2 and use a reviewed Microsoft package."
    }
    $uri = [uri]$urls[0]
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'download.microsoft.com') { throw "Microsoft Download Center returned an unexpected URL '$uri'." }
    if ([IO.Path]::GetFileName($uri.AbsolutePath) -ine $fileMatch.Value -or $fileMatch.Value -notmatch [regex]::Escape($cuMatch.Groups[2].Value)) { throw 'Microsoft CU filename, KB and download URL disagree.' }
    [pscustomobject]@{
        Name = "CU$($cuMatch.Groups[1].Value)"
        KB = $cuMatch.Groups[2].Value.ToUpperInvariant()
        Version = $versionMatch.Groups[1].Value
        FileName = $fileMatch.Value
        Uri = $uri.AbsoluteUri
    }
}

function Get-LatestPackage {
    param($Update)
    if (-not (Test-Path -LiteralPath $packageRoot)) { New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null }
    $destination = Join-Path $packageRoot $Update.FileName
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if($Update.PSObject.Properties.Name -contains 'Sha256' -and (Get-FileHash $destination -Algorithm SHA256).Hash -ne $Update.Sha256){throw 'Cached SQL package SHA-256 mismatch. Review/remove the corrupt cached file before retrying.'}
        return $destination
    }
    $partial = $destination + '.download'
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    Write-Host "Downloading $($Update.Name) $($Update.KB) from Microsoft..."
    try {
        $downloaded = $false
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try { Start-BitsTransfer -Source $Update.Uri -Destination $partial -DisplayName 'SQL Server update'; $downloaded = $true }
            catch { Write-Warning 'BITS unavailable; retrying the Microsoft package over HTTPS.'; Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
        }
        if (-not $downloaded) {
            Invoke-WebRequest -Uri $Update.Uri -OutFile $partial -UseBasicParsing
        }
        if($Update.PSObject.Properties.Name -contains 'Sha256' -and (Get-FileHash $partial -Algorithm SHA256).Hash -ne $Update.Sha256){throw 'Downloaded SQL package SHA-256 does not match Microsoft Catalog.'}
        Move-Item -LiteralPath $partial -Destination $destination
        return $destination
    }
    catch {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Convert-SqlHistory {
    param([string]$Html,[int]$Major)
    foreach($row in [regex]::Matches($Html,'<tr[^>]*>[\s\S]*?</tr>','IgnoreCase')){
        $cells=@([regex]::Matches($row.Value,'<td[^>]*>([\s\S]*?)</td>','IgnoreCase')|ForEach-Object{
            [regex]::Replace([Net.WebUtility]::HtmlDecode([regex]::Replace($_.Groups[1].Value,'<[^>]+>',' ')),'\s+',' ').Trim()
        })
        if($cells.Count-ne5-or$cells[0]-notmatch("^$Major\.0\.\d+\.\d+$")){continue}
        if($cells[2]-notmatch'^CU\d+(?:\s*\+\s*GDR)?$'-or$cells[3]-notmatch'^KB\d+$'){continue}
        $date=[datetime]::ParseExact($cells[4],'MMMM d, yyyy',[Globalization.CultureInfo]::InvariantCulture)
        [pscustomobject]@{Name=$cells[2];Version=$cells[0];KB=$cells[3];Released=$date.ToString('yyyy-MM-dd')}
    }
}

function Select-SqlUpdateStep {
    param([object[]]$History,[version]$CurrentVersion)
    $ordered=@($History|Sort-Object @{Expression={[version]$_.Version};Descending=$true})
    if(-not$ordered.Count){throw 'Microsoft history contains no supported CU/security builds. No older CU fallback is allowed.'}
    $target=$ordered[0]
    $step=$target
    if($target.Name-match'^(CU\d+)\s*\+\s*GDR$'){
        $baseName=$matches[1]
        $base=@($History|Where-Object Name -eq $baseName)
        if($base.Count-ne1){throw 'Security update prerequisite CU is ambiguous or missing.'}
        if($CurrentVersion-lt[version]$base[0].Version){$step=$base[0]}
    }
    [pscustomobject]@{Step=$step;Target=$target;IsPrerequisite=($step.Version-ne$target.Version)}
}

function Assert-SqlHistoryUpdate {
    param($Update,[int]$Major,[switch]$Prerequisite)
    $release=Get-SqlRelease $Major
    $kb=switch($Major){15{'kb4518398'}16{'kb5023451'}17{'kb5005684'}}
    $url='https://support.microsoft.com/en-us/servicing/sql/sql-server-'+$release.Year+'/'+$kb+'-build-versions'
    try { $html=(Invoke-WebRequest $url -UseBasicParsing -UserAgent 'SqlExpressWindowsMaintenance/1.2.0' -TimeoutSec 60).Content }
    catch {
        $url='https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-'+$release.Year+'/build-versions'
        $html=(Invoke-WebRequest $url -UseBasicParsing -UserAgent 'SqlExpressWindowsMaintenance/1.2.0' -TimeoutSec 60).Content
    }
    $found=$false;$highest=[version]'0.0'
    foreach($row in [regex]::Matches($html,'<tr[^>]*>[\s\S]*?</tr>','IgnoreCase')){
        $text=[regex]::Replace([Net.WebUtility]::HtmlDecode([regex]::Replace($row.Value,'<[^>]+>',' ')),'\s+',' ').Trim()
        $build=[regex]::Match($text,"^CU\d+(?:\s*\+\s*GDR)?(?:\s+\(Latest\))?\s+($Major\.0\.\d+\.\d+)\b",'IgnoreCase')
        if($build.Success-and[version]$build.Groups[1].Value-gt$highest){$highest=[version]$build.Groups[1].Value}
        $pattern='^'+[regex]::Escape($Update.Name)+'(?:\s+\(Latest\))?\s+'+[regex]::Escape($Update.Version)+'\s+.*?\b'+[regex]::Escape($Update.KB)+'\b'
        if($text-match$pattern){$found=$true}
    }
    if($found-and($Prerequisite-or[version]$Update.Version-eq$highest)){return}
    throw 'Microsoft build histories disagree on the selected SQL update. No older update will be substituted.'
}

function Get-CatalogSqlMedia {
    param($Update,[int]$Major)
    $year=(Get-SqlRelease $Major).Year
    if($Update.KB-notmatch'^KB\d+$'){throw 'Invalid KB identifier.'}
    $search=(Invoke-WebRequest ('https://www.catalog.update.microsoft.com/Search.aspx?q='+$Update.KB) -UseBasicParsing -TimeoutSec 60).Content
    $ids=@(foreach($m in [regex]::Matches($search,'([a-f0-9-]{36})_link[^>]*>([\s\S]*?)</a>','IgnoreCase')){
        $title=[regex]::Replace($m.Groups[2].Value,'<[^>]+>',' ')
        if($title-match("SQL Server\s+$year\b")-and$title-match('\b'+$Update.KB+'\b')){$m.Groups[1].Value}
    })
    $ids=@($ids|Select-Object -Unique)
    if($ids.Count-ne1){throw "Expected one SQL Server $year $($Update.KB) Catalog entry; found $($ids.Count). Use reviewed local media."}
    $body=@{updateIDs=(ConvertTo-Json -InputObject @(@{size=0;updateID=$ids[0];uidInfo=$ids[0]}) -Compress)}
    $dialog=(Invoke-WebRequest 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -UseBasicParsing -TimeoutSec 60).Content
    $urls=@([regex]::Matches($dialog,"downloadInformation\[0\]\.files\[(\d+)\]\.url\s*=\s*'([^']+)'")|Where-Object{
        $_.Groups[2].Value-match("/sqlserver$year-"+$Update.KB+'-x64(?:_[a-f0-9]+)?\.exe$')
    })
    if($urls.Count-ne1){throw 'Catalog did not return one matching x64 SQL executable.'}
    $uri=[uri]$urls[0].Groups[2].Value
    if($uri.Scheme-ne'https'-or$uri.Host-notin@('catalog.s.download.windowsupdate.com','download.windowsupdate.com','download.microsoft.com')){throw 'Unexpected Catalog download host.'}
    $index=$urls[0].Groups[1].Value
    $digest=[regex]::Match($dialog,"downloadInformation\[0\]\.files\[$index\]\.sha256\s*=\s*'([^']+)'")
    if(-not$digest.Success){throw 'Catalog SHA-256 missing.'}
    $bytes=[Convert]::FromBase64String($digest.Groups[1].Value)
    if($bytes.Length-ne32){throw 'Invalid Catalog SHA-256.'}
    [pscustomobject]@{Uri=$uri.AbsoluteUri;Sha256=([BitConverter]::ToString($bytes).Replace('-',''));FileName="SQLServer$year-$($Update.KB)-x64.exe"}
}

function Get-LatestUpdate {
    param([Parameter(Mandatory)][int]$Major,[Parameter(Mandatory)][version]$CurrentVersion)
    $null=Get-SqlRelease $Major
    if($CurrentVersion.Major-ne$Major){throw 'Current SQL version does not match selected major.'}
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $url='https://support.microsoft.com/en-us/servicing/sql/kb321185-download-and-install-latest-updates'
    $html=(Invoke-WebRequest $url -UseBasicParsing -UserAgent 'SqlExpressWindowsMaintenance/1.2.0' -TimeoutSec 60).Content
    $plan=Select-SqlUpdateStep @(Convert-SqlHistory $html $Major) $CurrentVersion
    Assert-SqlHistoryUpdate $plan.Target $Major
    if($plan.IsPrerequisite){Assert-SqlHistoryUpdate $plan.Step $Major -Prerequisite}
    $media=Get-CatalogSqlMedia $plan.Step $Major
    [pscustomobject]@{Name=$plan.Step.Name;KB=$plan.Step.KB;Version=$plan.Step.Version;Released=$plan.Step.Released;Uri=$media.Uri;FileName=$media.FileName;Sha256=$media.Sha256;IsPrerequisite=$plan.IsPrerequisite;FinalVersion=$plan.Target.Version;FinalName=$plan.Target.Name;FinalKB=$plan.Target.KB;FinalReleased=$plan.Target.Released}
}

function Test-Yes {
    param([string]$Answer)
    return $Answer -match '^(?i:y|yes|t|tak)$'
}
