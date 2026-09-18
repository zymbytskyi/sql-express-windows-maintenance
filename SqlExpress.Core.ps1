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
            if (([version][string]$row.ProductVersion).Major -eq 16 -and [string]$row.Edition -match 'Express') {
                $instances.Add([pscustomobject]@{
                    InstanceName = $instanceName
                    ServerInstance = $serverInstance
                    DisplayName = if ($instanceName -eq 'MSSQLSERVER') { "$env:COMPUTERNAME (default)" } else { "$env:COMPUTERNAME\$instanceName" }
                    Edition = [string]$row.Edition
                    Version = [string]$row.ProductVersion
                    Update = [string]$row.ProductUpdateLevel
                    IsSysadmin = [bool]$row.IsSysadmin
                })
            }
        }
        catch {
            Write-Warning "Could not query local instance '$serverInstance': $($_.Exception.Message)"
        }
    }
    return $instances.ToArray()
}

function Select-Instance {
    $instances = @(Get-LocalExpressInstances)
    if (-not $instances.Count) { throw 'No query-ready local SQL Server 2022 Express instance was found.' }
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

function Get-LatestUpdate {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing
    $html = [Net.WebUtility]::HtmlDecode([string]$response.Content)
    $plain = [regex]::Replace($html, '<script[\s\S]*?</script>|<style[\s\S]*?</style>|<[^>]+>', ' ')
    $plain = [regex]::Replace($plain, '\s+', ' ')
    $fileMatch = [regex]::Match($plain, 'SQLServer2022-KB\d+-x64\.exe', 'IgnoreCase')
    $versionMatch = [regex]::Match($plain, 'Version:\s*(16\.0\.\d+\.\d+)', 'IgnoreCase')
    $cuMatch = [regex]::Match($plain, 'Cumulative Update Package\s+(\d+)\s+for SQL Server 2022\s+-\s+(KB\d+)', 'IgnoreCase')
    $urls = @($response.Links | ForEach-Object {
        if ($_.PSObject.Properties.Name -contains 'href') { [string]$_.href }
    } | Where-Object { $_ -match '^https://download\.microsoft\.com/.*/SQLServer2022-KB\d+-x64\.exe(?:\?.*)?$' })
    if (-not $urls.Count) {
        $urlMatch = [regex]::Match($html, 'https://download\.microsoft\.com/[^"''\s<>]+/SQLServer2022-KB\d+-x64\.exe(?:\?[^"''\s<>]*)?', 'IgnoreCase')
        if ($urlMatch.Success) { $urls = @($urlMatch.Value) }
    }
    if (-not $fileMatch.Success -or -not $versionMatch.Success -or -not $cuMatch.Success -or -not $urls.Count) {
        throw 'Could not read the current SQL Server 2022 CU from Microsoft Download Center. Choose option 2 and use a downloaded Microsoft package.'
    }
    $uri = [uri]$urls[0]
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'download.microsoft.com') { throw "Microsoft Download Center returned an unexpected URL '$uri'." }
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
    if (Test-Path -LiteralPath $destination -PathType Leaf) { return $destination }
    $partial = $destination + '.download'
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    Write-Host "Downloading $($Update.Name) $($Update.KB) from Microsoft..."
    try {
        $downloaded = $false
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try { Start-BitsTransfer -Source $Update.Uri -Destination $partial -DisplayName 'SQL Server 2022 CU'; $downloaded = $true }
            catch { Write-Warning 'BITS unavailable; retrying the Microsoft package over HTTPS.'; Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
        }
        if (-not $downloaded) {
            Invoke-WebRequest -Uri $Update.Uri -OutFile $partial -UseBasicParsing
        }
        Move-Item -LiteralPath $partial -Destination $destination
        return $destination
    }
    catch {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Test-Yes {
    param([string]$Answer)
    return $Answer -match '^(?i:y|yes|t|tak)$'
}
