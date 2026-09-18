# SQL Express + Windows Maintenance

Separate local PowerShell 5.1 tool for SQL Server 2022 Express hosts. The original Express-only repository remains unchanged.

## Install

In an elevated Windows PowerShell console, install directly from GitHub:

```powershell
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$p=Join-Path $env:TEMP 'Install-SqlExpressWindowsPatch.ps1'
Invoke-WebRequest 'https://raw.githubusercontent.com/zymbytskyi/sql-express-windows-maintenance/v1.0.0/Install-FromGitHub.ps1' -UseBasicParsing -OutFile $p
if((Get-FileHash $p).Hash-ne'4F2D117DB6703135D882645BAA449D414E85A4811E4E91F5EE68712C80ABBC7C'){throw 'Bootstrap hash mismatch'}
& $p
```

The bootstrap verifies the GitHub release digest and the installer verifies the file manifest. Internet access to GitHub is required for this method.

Download the release ZIP, extract to a temporary directory and run `SqlExpressWindowsPatch\Install.cmd` as Administrator. Files install into `C:\SqlExpressWindowsPatch`; upgrades preserve `Runs` and `Packages`. Do not extract over an existing installation.

## Use

Open Windows PowerShell as Administrator:

```powershell
cd C:\SqlExpressWindowsPatch
.\Start-ServerMaintenance.ps1
```

1. SQL Express only.
2. Windows Update only.
3. Windows Update followed by SQL Express.

Review backup dates, optionally create COPY_ONLY + CHECKSUM backups of master/model/msdb with VERIFYONLY, then review the update list and confirm. Windows updates are taken from the existing Windows Update/WSUS source. Drivers, optional/preview updates, OS feature upgrades, updates requiring input, and SQL updates are excluded from the Windows batch. SQL is handled separately with instance checks; no claim that every Microsoft product update is included.

If Windows needs a restart, approve it or restart later. After signing in, run the same script and agree to resume. It rescans Windows Update for dependencies before continuing to SQL. Up to three batches are processed per invocation; further batches require another invocation. No scheduled task, automatic logon, or automatic post-reboot execution.

Progress includes stage, elapsed time and Windows Update percentage where available. Logs and update results are in `Runs`; SQL Setup logs are in `%ProgramFiles%\Microsoft SQL Server\160\Setup Bootstrap\Log`. A stopped automatic non-SQL service is a warning requiring review, not silently started by this tool.

Read-only system/update inspection (writes diagnostic logs only):

```powershell
.\Start-ServerMaintenance.ps1 -Mode Check
```

Current-account automation can use `-Mode All -Confirm -BackupChoice 1 -InstanceName SQLEXPRESS`. This explicitly approves eligible update installation and license terms, but **never authorizes an automatic reboot**. Relaunch with `-Resume` after a manual restart. Use `-LocalPackagePath` for reviewed SQL media.

Use a maintenance window and a tested OS recovery plan. Old database backups are informational, not an age-based blocker. Disk preflight reserves 5 GiB plus the reported maximum undownloaded package size; this conservative check is not a guarantee of sufficient Windows servicing space. No automatic cleanup or uninstall is performed.

See SECURITY.md for recovery and policy limits. Latest SQL CU metadata is cross-checked against Microsoft build history; inconsistent sources block automatic selection.

## Tested scope (2026-09-18)

- Real Windows Server 2025 lab: installed KB5122871 (OS build 26100.33438), KB5126052 (.NET), KB890830, KB4052623 and KB2267602. Each returned success; Windows Update history was checked again after restart.
- Verified system COPY_ONLY backups, pre-restart continuation blocking, graceful restart, saved-run continuation, clean Windows rescan and two final SQL/database/service probes.
- SQL Server 2022 Express was already on CU27 (16.0.4295.3): latest-CU/local-media no-op paths passed. A new SQL CU was not installed in this run. The quiet installer wrapper has mocked argument/exit-code tests; this is not a fresh SQL Setup acceptance claim.
- Automatic delayed-start SQL services are awaited on restart continuation, without changing their startup mode or starting unrelated services.
- Package installation/upgrade preservation and regression tests cover filtering, partial failure, download/disk/busy gates, machine-bound state and uncertain installation outcomes.

Other Windows Server versions and client WSUS configurations need their own acceptance test. Lab success is not production certification.
