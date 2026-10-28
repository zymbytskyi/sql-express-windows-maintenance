# Validation boundaries

- 2.0.0 supports all local SQL 2017/2019/2022/2025 editions and multi-instance sequential runs. Regression and live metadata checks pass; backup/Setup integration was mocked. Perform real installation acceptance and restore/recovery checks in a non-production environment before production use.

- 1.2.1 supersedes the incorrect 1.2.0 intermediate-CU policy. Single-package installation and reboot-to-verification tests passed with mocked Setup; live metadata checks passed for 2019/2022/2025. Real installation acceptance is still required before production rollout.

- 1.2.0 (superseded): metadata checks passed, but CU-to-security mocks encoded an incorrect prerequisite assumption. Do not use that version for new maintenance runs.

- 1.1.0: Express 2019/2022/2025 regression and live Microsoft metadata checks passed in Windows PowerShell 5.1. Real installation acceptance for 2019 and 2025 remains to be performed before production rollout; this release does not claim it.

- Windows Server 2025 combined acceptance completed on 2026-09-18: five Windows updates, verified system backups, restart/continuation, clean rescan and final SQL health. SQL Express CU27 was already installed and was not reinstalled.
- Test other Windows Server versions and customer WSUS policies separately; no certification beyond the documented lab run.
- Interrupted/failed installation requires review; do not erase state to bypass the gate. Automatic rollback and remote orchestration are outside scope.
