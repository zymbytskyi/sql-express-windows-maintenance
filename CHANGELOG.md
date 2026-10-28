# Changelog

## 1.2.1 - 2026-10-28

- Correct the unsupported assumption that CU+GDR requires its named CU to be installed separately. Select and install the latest package directly, once, without an intermediate CU or extra reboot.
- Continue to final health verification after a successful installation/restart. Preserve support for existing 1.2.0 SQL-phase restart journals and uncertain-outcome safeguards.
- Regression tests cover direct installation, reboot continuation, already-current/newer builds and journal compatibility. Live Microsoft metadata checks passed for all supported majors; real SQL installation was not performed.
- Document Microsoft prerequisites and explicitly supersede the incorrect 1.2.0 guidance.

## 1.2.0 - 2026-10-28

- Automatic selection now targets the latest CU-branch build, including security/CU+GDR releases, rather than the latest CU alone; display KB, build and release date.
- Verify the newest target against independent Microsoft build history and retrieve matching x64 media plus SHA-256 from Microsoft Update Catalog. Never silently fall back to an older update.
- Install and verify a required base CU before the security update; preserve SQL continuation if a prerequisite requires restart. No forced or automatic reboot was added.
- Check cached/downloaded media against Catalog SHA-256 in addition to existing Microsoft signature and target-major checks.
- PowerShell 5.1 selection/orchestration regression tests and live Microsoft metadata checks passed; real SQL/security installation was not performed in this release.

## 1.1.0 - 2026-10-28

- Support standalone Express 2019/2022/2025, including mixed supported versions on one host, with per-instance diagnostics.
- Route CU discovery, independent Microsoft history validation, package filename/product-major validation and Setup log location by the selected instance version.
- Reject wrong-major media and downloaded package builds that disagree with selected CU metadata; retain all existing standalone, signature, sysadmin and restart gates.
- Add Microsoft localized build-history fallback for failing Learn redirects.
- Add PowerShell 5.1 multi-version regression and live metadata tests. No fresh SQL 2019/2025 installation acceptance is claimed.

## 1.0.0

- Separate local SQL Server 2022 Express + Windows Server maintenance package; original Express-only tool unchanged.
- Windows-only, SQL-only and combined workflows; manual restart with persisted continuation.
- Native Windows Update Agent, configured update source, per-update results, live elapsed time/progress and explicit EULA approval.
- Excludes drivers, optional/preview, OS feature upgrades and SQL updates from Windows batches; exclusive updates are installed separately.
- Verified system COPY_ONLY backups, standalone/edition/permissions/disk checks, protected machine-bound state, update failure gates and final SQL/service/database checks.
- Quiet SQL setup with visible heartbeat; no scheduled tasks or security-policy bypasses.
- Real five-update Windows Server 2025 installation, restart/resume and final SQL health acceptance passed on 2026-09-18. SQL CU27 already-current handling was verified; no new SQL CU was installed in this run.
- Added bounded waiting for delayed automatic SQL services after restart, without changing service configuration.
