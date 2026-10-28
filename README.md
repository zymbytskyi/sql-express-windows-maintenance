# SQL Express + Windows Maintenance

Separate local PowerShell 5.1 tool for SQL Server 2019, 2022 and 2025 Express hosts. Multiple supported Express versions may coexist; select one SQL instance per run. All local instances must be accessible and supported Express editions. The original Express-only repository remains unchanged.

## Install

In an elevated Windows PowerShell console, install directly from GitHub:

```powershell
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$p=Join-Path $env:TEMP 'Install-SqlExpressWindowsPatch.ps1'
Invoke-WebRequest 'https://raw.githubusercontent.com/zymbytskyi/sql-express-windows-maintenance/v1.2.1/Install-FromGitHub.ps1' -UseBasicParsing -OutFile $p
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

Progress includes stage, elapsed time and Windows Update percentage where available. Logs and update results are in `Runs`; SQL Setup logs are in `%ProgramFiles%\Microsoft SQL Server\150\Setup Bootstrap\Log` (2019), `160` (2022) or `170` (2025). A stopped automatic non-SQL service is a warning requiring review, not silently started by this tool.

Read-only system/update inspection (writes diagnostic logs only):

```powershell
.\Start-ServerMaintenance.ps1 -Mode Check
```

Current-account automation can use `-Mode All -Confirm -BackupChoice 1 -InstanceName SQLEXPRESS`. This explicitly approves eligible update installation and license terms, but **never authorizes an automatic reboot**. Relaunch with `-Resume` after a manual restart. Use `-LocalPackagePath` for reviewed SQL media.

Use a maintenance window and a tested OS recovery plan. Old database backups are informational, not an age-based blocker. Disk preflight reserves 5 GiB plus the reported maximum undownloaded package size; this conservative check is not a guarantee of sufficient Windows servicing space. No automatic cleanup or uninstall is performed.

See SECURITY.md for recovery and policy limits. Latest SQL update metadata is cross-checked against two Microsoft build histories; inconsistent or unavailable sources block automatic selection rather than silently choosing an older CU.

Automatic selection chooses the highest released CU-branch build for the installed major version, including CU+GDR security updates. It displays the KB, build and release date. RTM/GDR-only packages are not mixed into the CU branch; this policy may move an RTM/GDR-only instance to the CU branch after installation approval. It installs the selected package directly, without inferring an intermediate CU dependency from the package name. A required restart saves continuation to health verification; relaunch the same script after restarting. The tool never downgrades or changes SQL major versions. Microsoft Catalog provides the matching x64 EXE and SHA-256; both newly downloaded and cached files are checked before signature and product-version validation. Catalog filenames are normalized to SQLServerYEAR-KBnumber-x64.exe without altering file contents. Reviewed local media remains an explicit manual override, not a claim of latest status. Standard/Developer editions, AG and FCI remain unsupported.

## 1.2.1 correction and validation (2026-10-28)

Use 1.2.1 instead of 1.2.0. The intermediate-CU rule in 1.2.0 was incorrect. Microsoft's prerequisites for [SQL 2019 KB5128494](https://support.microsoft.com/en-us/help/5128494) and [SQL 2022 KB5126934](https://support.microsoft.com/en-us/help/5126934) permit the corresponding SQL release or previous CUs; the CU named in CU+GDR is not a required separate installation. Review the selected KB's prerequisites and known issues for your environment; SQL Setup remains authoritative for applicability and failures are not retried with an invented prerequisite.

PowerShell 5.1 tests verify one direct Setup invocation, reboot continuation to verification, no reinstall/downgrade, and compatibility with saved 1.2.0 restart journals. Live Microsoft history/Catalog discovery passed for Express 2019/2022/2025. Installations were mocked: this release has not received a real SQL/security installation acceptance test. If upgrading after 1.2.0 installed a base CU, preserve Runs and resume after any requested restart; the SQL phase now selects the latest package directly. Unknown/failed installer outcomes still require manual review.

## 1.2.0 validation (2026-10-28)

Historical record only: superseded by 1.2.1. These tests encoded the incorrect intermediate-CU assumption and did not establish that it was required.

PowerShell 5.1 tests cover CU/security ordering, prerequisite CU installation followed by security installation, reboot continuation after the prerequisite, newer CU supersedence, branch separation, missing metadata, and Catalog host/hash/ambiguity rejection. SQL Setup was mocked, not run. Live Microsoft histories and Catalog metadata resolved 2019 CU32+GDR (15.0.4500.2), 2022 CU27+GDR (16.0.4305.5), and 2025 CU10 (17.0.5035.5). Builds are discovered at runtime, not hard-coded. No real security-update installation acceptance was performed for this release.

## 1.1.0 validation (2026-10-28)

Windows PowerShell 5.1 regression tests cover all three Express major versions, mixed-version discovery, unavailable/non-Express instances, per-version CU selection, Microsoft metadata disagreement, invalid signatures and wrong-major media. Live Microsoft metadata checks passed for all three releases. No real SQL 2019 or 2025 installation was performed for this release; validate in a non-production environment before production use. The Windows Update/reboot workflow is unchanged.

## Tested scope (2026-09-18)

- Real Windows Server 2025 lab: installed KB5122871 (OS build 26100.33438), KB5126052 (.NET), KB890830, KB4052623 and KB2267602. Each returned success; Windows Update history was checked again after restart.
- Verified system COPY_ONLY backups, pre-restart continuation blocking, graceful restart, saved-run continuation, clean Windows rescan and two final SQL/database/service probes.
- SQL Server 2022 Express was already on CU27 (16.0.4295.3): latest-CU/local-media no-op paths passed. A new SQL CU was not installed in this run. The quiet installer wrapper has mocked argument/exit-code tests; this is not a fresh SQL Setup acceptance claim.
- Automatic delayed-start SQL services are awaited on restart continuation, without changing their startup mode or starting unrelated services.
- Package installation/upgrade preservation and regression tests cover filtering, partial failure, download/disk/busy gates, machine-bound state and uncertain installation outcomes.

Other Windows Server versions and client WSUS configurations need their own acceptance test. Lab success is not production certification.
