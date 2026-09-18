# Repository guidance

- Local Windows PowerShell 5.1 only; standalone Windows Server with SQL Server 2022 Express.
- Keep documentation and console output English. Preserve the separate Express-only repository.
- Do not modify update sources, WSUS policy, Defender configuration, or automatic-restart policy.
- No scheduled resume, automatic login or stored credentials. Every reboot needs separate approval.
- Persist state before changes; never retry unknown installation outcomes blindly.
- Run Test-Package.ps1 and Test-Behavior.ps1 after changes. Update CHANGELOG.md and NEXT-STEPS.md.
- Keep runtime data, credentials, backups and update media out of Git. Commit and publish only when explicitly requested.
