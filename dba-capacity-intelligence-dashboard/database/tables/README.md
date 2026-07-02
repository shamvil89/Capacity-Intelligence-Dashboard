# Database Tables

## Purpose

The `database/tables` folder contains table creation scripts for the `DBAUtility` repository. These scripts define the persistent storage used by collectors, forecasts, alerts, and the API.

The files are numbered so deployment order is predictable.

## Table Scripts

| Script | Table | Purpose |
| --- | --- | --- |
| `001_ServerInventory.sql` | `dbo.ServerInventory` | Stores monitored server inventory, source type, connection mode, credential key, and active flag. |
| `002_DatabaseSizeHistory.sql` | `dbo.DatabaseSizeHistory` | Stores database size, data size, and log size by collection time. |
| `003_FileSizeHistory.sql` | `dbo.FileSizeHistory` | Stores logical file size, used space, free space, growth setting, and max size. |
| `004_DiskSpaceHistory.sql` | `dbo.DiskSpaceHistory` | Stores server volume total/free space and free percentage. |
| `005_TableSizeHistory.sql` | `dbo.TableSizeHistory` | Stores table size, data size, index size, and row count history. |
| `006_BackupSizeHistory.sql` | `dbo.BackupSizeHistory` | Stores backup size and compressed backup size history. |
| `007_TempDBUsageHistory.sql` | `dbo.TempDBUsageHistory` | Stores TempDB size and used space snapshots. |
| `008_CapacityForecastResult.sql` | `dbo.CapacityForecastResult` | Stores latest capacity forecast output and risk classification. |
| `009_AlertHistory.sql` | `dbo.AlertHistory` | Stores alerts raised by forecast logic and collector failure handling, including active/resolved state and the resolution source. |
| `010_LongRunningTransactionHistory.sql` | `dbo.LongRunningTransactionHistory` | Stores open transaction evidence, SQL text, and cached XML query plan when available. |
| `011_TempDBSessionUsageHistory.sql` | `dbo.TempDBSessionUsageHistory` | Stores top session-level TempDB consumers for alert drill-through. |
| `012_BlockingSessionHistory.sql` | `dbo.BlockingSessionHistory` | Stores lead blocker, blocked request, wait, object, SQL text, lock, and cached query plan evidence. |
| `013_AlwaysOnHealthHistory.sql` | `dbo.AlwaysOnHealthHistory` | Stores Always On replica/database synchronization and health evidence. |
| `014_ReplicationHealthHistory.sql` | `dbo.ReplicationHealthHistory` | Stores replication database flags and replication agent status/error evidence. |
| `015_AlertThresholdSetting.sql` | `dbo.AlertThresholdSetting` | Stores editable alert and forecast threshold settings used by `dbo.usp_GenerateCapacityForecast` and `dbo.usp_GenerateAlerts`. |
| `016_ApplicationCmdb.sql` | `dbo.ApplicationCmdb`, `dbo.ApplicationDatabaseMapping` | Stores application ownership/contact details and maps applications to databases across servers. |
| `017_AutoHealHistory.sql` | `dbo.AutoHealRequest`, `dbo.AutoHealFileCandidate` | Stores dashboard-triggered auto-heal pipeline requests, durable run status, result JSON, and backup-file cleanup candidates. |
| `018_AlertWorkNote.sql` | `dbo.AlertWorkNote` | Stores alert work notes from auto-heal runs and dashboard user comments. |

## ServerInventory Details

`dbo.ServerInventory` drives collection. Important fields:

| Column | Meaning |
| --- | --- |
| `server_name` | Source SQL Server instance or Azure SQL logical server. |
| `environment` | Business environment label. |
| `server_type` | `SQLServer`, `AzureSQL`, or `ManagedInstance`. |
| `connection_mode` | `SqlAuth`, `WindowsAuth`, `AzureADPassword`, `AzureADIntegrated`, or `ManagedIdentity`. |
| `credential_key` | Key used to select credentials from `SOURCE_SQL_CREDENTIALS_JSON`. |
| `is_active` | Controls whether the collector processes the server. |

Example:

```sql
INSERT INTO dbo.ServerInventory
(
    server_name,
    environment,
    server_type,
    connection_mode,
    credential_key,
    is_active
)
VALUES
(
    N'prod-sql-01',
    'Production',
    'SQLServer',
    'SqlAuth',
    'prod',
    1
);
```

## History Table Pattern

## Connection Mode Reference

| Mode | Intended use |
| --- | --- |
| `SqlAuth` | SQL username/password for SQL Server or Azure SQL Database. |
| `WindowsAuth` | Trusted SQL Server connection using the Windows identity running the collector. |
| `AzureADPassword` | Azure SQL Database authentication using an Entra ID user/password. |
| `AzureADIntegrated` | Azure SQL Database integrated authentication using the running Windows identity. |
| `ManagedIdentity` | Future token-based path; not implemented by the current Windows PowerShell collector. |

For `WindowsAuth`, SQL Server does not accept a Windows username/password in the connection string. Grant SQL permissions to the Azure DevOps agent service account, a domain service account, or a gMSA.

For `AzureADIntegrated`, the agent host and service identity must be able to perform integrated Entra ID authentication to Azure SQL Database.

Most metric history tables include:

- Identity primary key
- `collection_time`
- `server_name`
- Metric dimensions, such as database, file, volume, or table
- Numeric capacity values

The collector inserts rows every run. Forecast procedures query recent history to calculate growth and risk.

Long-running transaction and blocking history also keep XML execution plan columns. These are best-effort cached plans from SQL Server DMVs and can be null when SQL Server does not expose a plan handle or the collector identity lacks permission.

## AlertHistory Details

`dbo.AlertHistory` stores both forecast alerts and collection failure alerts.

Important lifecycle columns:

| Column | Meaning |
| --- | --- |
| `is_resolved` | `0` for active alerts and `1` for alerts moved to history. |
| `resolved_at` | Time the collector or alert generator confirmed the condition was gone. |
| `resolved_by` | `Collector` for normal retirement, `AutoHeal:<ActionType>` when a completed auto-heal request existed for that alert before the next alert-generation run retired it. |

Common alert types:

```text
CollectionFailure:DatabaseSize
CollectionFailure:FileSize
CollectionFailure:DiskSpace
CapacityRisk
```

The dashboard reads active unresolved rows from `dbo.vw_ActiveAlerts`.

## AlertThresholdSetting Details

`dbo.AlertThresholdSetting` is the source of truth for alert tuning. The Settings page reads this table through the API and updates `setting_value_decimal`.

Important columns:

| Column | Meaning |
| --- | --- |
| `alert_type` | Logical alert family, such as `LogFileGrowthSpike`, `BlockingChain`, or `DiskSpaceLow`. |
| `setting_key` | Stable machine-readable setting name used by stored procedures. |
| `display_name` | Human-readable label shown in the Settings page. |
| `setting_value_decimal` | Current active threshold value. |
| `default_value_decimal` | Product default used by the Reset action. |
| `minimum_value_decimal` / `maximum_value_decimal` | Optional validation range enforced by SQL and the API. |

Deployment reruns the seed script with `MERGE`. Existing customized `setting_value_decimal` values are preserved; metadata, descriptions, defaults, and ranges are refreshed from source control.

`LogShrinkAutoHeal` settings control the transaction log shrink target:

| Setting | Meaning |
| --- | --- |
| `MinimumTargetSizeMb` | Lowest MB target passed to `DBCC SHRINKFILE`; default `256`. |
| `UsedLogMultiplier` | Keeps target above current used log space; default `2`. |

Auto-heal stores the requested target and post-shrink size in `dbo.AutoHealRequest.details_json`. If SQL Server leaves the file larger than requested, the UI and email text call that out because the active log tail or VLF layout may prevent shrinking lower during that run.

## Application CMDB Details

`dbo.ApplicationCmdb` stores one row per application. `dbo.ApplicationDatabaseMapping` maps that application to one or more databases across one or more SQL Server instances.

Important `dbo.ApplicationCmdb` fields:

| Column | Meaning |
| --- | --- |
| `application_name` | Required application name. This is unique and reused when another database maps to the same application. |
| `prodops_team_email` | Optional ProdOps team email or distribution list. |
| `application_owner_email` | Optional application owner email. |
| `business_owner_email` | Optional business owner email. |
| `support_dl_email` | Optional support distribution list. |
| `escalation_dl_email` | Optional escalation distribution list. |
| `servicenow_group` | Optional ServiceNow assignment group. |
| `criticality`, `application_url`, `notes` | Optional operational metadata. |

`dbo.ApplicationDatabaseMapping` has a unique `(server_name, database_name)` constraint so one database maps to one owning application. One application can have many mapped databases.

## AutoHeal Details

`dbo.AutoHealRequest` stores each dashboard-triggered remediation request and the latest Azure DevOps state. The More info popup reloads this table, so auto-heal status survives closing and reopening the popup.

Important fields:

| Column | Meaning |
| --- | --- |
| `alert_id` | Alert that requested the remediation. |
| `action_type` | `BackupRetentionScan`, `DeleteSelectedBackupFiles`, or `LogShrinkAssessment`. |
| `status` | Queued, Running, Completed, Failed, or the latest controlled state. |
| `pipeline_run_id`, `pipeline_web_url` | Azure DevOps run reference. |
| `details_json` | Action-specific result payload. Log shrink stores used log, target settings, requested target, post-shrink size, and whether SQL Server stopped above target. |

`dbo.AutoHealFileCandidate` stores `.bak` and `.trn` files discovered by backup cleanup scans. User-selected cleanup reads these candidate rows rather than accepting arbitrary paths from the browser.

## Alert Work Note Details

`dbo.AlertWorkNote` stores the operational timeline for an alert.

Work note sources:

| Source | Meaning |
| --- | --- |
| `Dashboard` | User-entered comments from the alert More info popup. |
| `AzureDevOps` | Queue, queue-failure, and status-refresh notes from the API. |
| `AutoHealPipeline` | Running/completed/failed notes written by `collector/Invoke-AutoHeal.ps1`. |

Important columns:

| Column | Meaning |
| --- | --- |
| `alert_id` | Alert that owns the work note. Notes are deleted when the alert is deleted. |
| `request_id` | Auto-heal request that produced the note, when applicable. |
| `note_type` | Machine-readable type such as `AutoHealQueued`, `AutoHealCompleted`, or `UserComment`. |
| `note_text` | Human-readable note body shown in the dashboard. |
| `details_json` | Optional structured payload for auto-heal results or queue metadata. |

## CapacityForecastResult Details

`dbo.CapacityForecastResult` stores calculated capacity information:

- Current size
- 7-day growth
- 30-day growth
- Average growth per day
- Estimated days remaining
- Risk level
- Recommendation text

This table is regenerated by `dbo.usp_GenerateCapacityForecast`.

## Customer Lift-And-Shift Notes

For customer deployments:

1. Do not manually create these tables unless the pipeline is unavailable.
2. Run `deploy-database.yml` so table scripts and incremental schema updates are applied in order.
3. Verify `credential_key` exists on `dbo.ServerInventory`.
4. Plan retention for history tables before production use.
5. Consider partitioning or purge jobs if collection frequency is high.

## Validation

```sql
USE DBAUtility;

SELECT name
FROM sys.tables
WHERE schema_id = SCHEMA_ID(N'dbo')
ORDER BY name;
```

```sql
SELECT COL_LENGTH(N'dbo.ServerInventory', N'credential_key') AS credential_key_exists;
```
