# Auto-Heal

## Purpose

The `autoheal` folder contains controlled remediation scripts that are triggered by the DBA Capacity dashboard through Azure DevOps.

Auto-heal scripts are intentionally separate from the metric collectors:

- `collector` gathers evidence and writes history tables.
- `autoheal` performs approved remediation actions requested from alert More info.
- Shared repository/source connection helpers remain in `collector/Common.ps1`.

## Scripts

| Script | Purpose |
| --- | --- |
| `Invoke-AutoHeal.ps1` | Entry point for `pipelines/auto-heal.yml`. Runs backup retention scans, selected backup-file cleanup, and log shrink assessment. |

## Supported Actions

| Action | Purpose |
| --- | --- |
| `BackupRetentionScan` | For `DiskSpaceLow` alerts. Scans known volumes or a target path, deletes eligible `.bak`/`.trn` files older than retention, and records remaining files for dashboard selection. |
| `DeleteSelectedBackupFiles` | Deletes only dashboard-selected file candidates from a previous scan. |
| `LogShrinkAssessment` | For log-file alerts. Checks open transactions, used log space, log reuse wait, and file size before attempting `DBCC SHRINKFILE`. |

## Operational Notes

- The Azure DevOps pipeline passes `requestId`, `serverName`, `databaseName`, `backupScanPath`, and `retentionDays`.
- Status and results are written to `dbo.AutoHealRequest`.
- Backup cleanup candidates are written to `dbo.AutoHealFileCandidate`.
- Queue/running/completion/failure events are appended to `dbo.AlertWorkNote`.
- The script imports `collector/Common.ps1` for repository connections, source SQL credentials, and dbatools initialization.

## Validation

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    "autoheal\Invoke-AutoHeal.ps1",
    [ref]$tokens,
    [ref]$errors
) | Out-Null
$errors
```
