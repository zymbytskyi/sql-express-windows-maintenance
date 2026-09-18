# Validation boundaries

- Windows Server 2025 combined acceptance completed on 2026-09-18: five Windows updates, verified system backups, restart/continuation, clean rescan and final SQL health. SQL Express CU27 was already installed and was not reinstalled.
- Test other Windows Server versions and customer WSUS policies separately; no certification beyond the documented lab run.
- Interrupted/failed installation requires review; do not erase state to bypass the gate. Automatic rollback and remote orchestration are outside scope.
