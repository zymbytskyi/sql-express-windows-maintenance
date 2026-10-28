# Security and scope

Run locally in elevated Windows PowerShell 5.1 using your existing Windows account. Local administrator and SQL sysadmin are required. Only standalone Windows Server hosts containing query-ready SQL Server 2017, 2019, 2022 or 2025 Database Engine instances are in scope. All local editions (EngineEdition 2, 3, 4), including Standard Developer, are supported. Inaccessible instances, unsupported versions/engines and any WSFC/AG/FCI configuration block the entire host. No remote patching, cloud database services, drivers or OS feature upgrades. New runs patch all local SQL instances sequentially unless narrowed with -InstanceName; persisted old scopes remain unchanged.

Missing/old full-backup history requires explicit risk acceptance. -Confirm does not imply -AcceptBackupRisk. A green history status does not verify external media, log-chain completeness, RPO or restore capability. New optional system backups use COPY_ONLY,CHECKSUM and VERIFYONLY; arrange a tested user-database and OS recovery plan separately.

Windows Update uses the existing WUA source and policies. It never registers Microsoft Update, bypasses WSUS, disables Defender, adds exclusions, or modifies Windows Update reboot policy. Existing corporate automatic restart policies still apply; use an approved maintenance window.

The explicit installation confirmation accepts vendor update EULAs. SQL media requires a Microsoft signature and version check. Review CU known issues. No scheduler or startup task is created. Reboot requires a separate interactive confirmation; unattended `-Confirm` never reboots automatically.

Runtime state is restricted to Administrators and SYSTEM. Installer scripts must be installed in an administrator-controlled directory. Keep logs, machine details, downloaded media and backups out of Git.

An interrupted installation or failed Windows batch is not blindly retried. Review current.json, Windows Update history and SQL Setup logs before recovery. Never delete state to bypass an active installer. Database backups are not an OS rollback strategy; arrange a tested VM/OS recovery plan separately. This tool does not create hypervisor checkpoints or promise update rollback.
