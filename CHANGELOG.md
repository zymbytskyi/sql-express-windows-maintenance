# Changelog

## 1.0.0

- Separate local SQL Server 2022 Express + Windows Server maintenance package; original Express-only tool unchanged.
- Windows-only, SQL-only and combined workflows; manual restart with persisted continuation.
- Native Windows Update Agent, configured update source, per-update results, live elapsed time/progress and explicit EULA approval.
- Excludes drivers, optional/preview, OS feature upgrades and SQL updates from Windows batches; exclusive updates are installed separately.
- Verified system COPY_ONLY backups, standalone/edition/permissions/disk checks, protected machine-bound state, update failure gates and final SQL/service/database checks.
- Quiet SQL setup with visible heartbeat; no scheduled tasks or security-policy bypasses.
- Real five-update Windows Server 2025 installation, restart/resume and final SQL health acceptance passed on 2026-09-18. SQL CU27 already-current handling was verified; no new SQL CU was installed in this run.
- Added bounded waiting for delayed automatic SQL services after restart, without changing service configuration.
