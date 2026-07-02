# Auto-Heal

## Purpose

The `autoheal` folder contains controlled remediation scripts that are triggered by the DBA Capacity dashboard through Azure DevOps.

Auto-heal scripts are intentionally separate from the metric collectors:

- `collector` gathers evidence and writes history tables.
- `autoheal` performs approved remediation actions requested from alert More info.
- Shared repository/source connection helpers remain in `collector/Common.ps1`.
- Auto-heal-specific shared helpers live in `autoheal/Common.ps1`.

## Scripts

| Script | Purpose |
| --- | --- |
| `Invoke-AutoHeal.ps1` | Thin dispatcher used by `pipelines/auto-heal.yml`. Validates shared parameters and routes to the selected category script. |
| `Common.ps1` | Shared auto-heal helpers for request status, work notes, SQL value conversion, threshold lookup, and source inventory resolution. |
| `BackupRetention.ps1` | Backup cleanup category. Contains backup scan, retention deletion, protected-name checks, Windows-folder skip logic, and selected file cleanup. |
| `LogShrink.ps1` | Transaction log category. Contains safety checks and conservative `DBCC SHRINKFILE` logic. |

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
- `Invoke-AutoHeal.ps1` imports `collector/Common.ps1` for repository connections, source SQL credentials, and dbatools initialization.
- `Invoke-AutoHeal.ps1` imports the category scripts in this folder, so the pipeline path stays stable while remediation logic is easier to manage.

## Validation

```powershell
Get-ChildItem .\autoheal -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    $errors
}
```
