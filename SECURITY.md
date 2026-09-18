# Security and scope

Run locally in elevated Windows PowerShell 5.1 using your existing Windows account. Local administrator and SQL sysadmin are required. Only standalone Windows Server hosts containing query-ready SQL Server 2022 Express instances are in scope. No remote patching, clusters, AG, FCI, drivers or OS feature upgrades.

Windows Update uses the existing WUA source and policies. It never registers Microsoft Update, bypasses WSUS, disables Defender, adds exclusions, or modifies Windows Update reboot policy. Existing corporate automatic restart policies still apply; use an approved maintenance window.

The explicit installation confirmation accepts vendor update EULAs. SQL media requires a Microsoft signature and version check. Review CU known issues. No scheduler or startup task is created. Reboot requires a separate interactive confirmation; unattended `-Confirm` never reboots automatically.

Runtime state is restricted to Administrators and SYSTEM. Installer scripts must be installed in an administrator-controlled directory. Keep logs, machine details, downloaded media and backups out of Git.

An interrupted installation or failed Windows batch is not blindly retried. Review current.json, Windows Update history and SQL Setup logs before recovery. Never delete state to bypass an active installer. Database backups are not an OS rollback strategy; arrange a tested VM/OS recovery plan separately. This tool does not create hypervisor checkpoints or promise update rollback.
