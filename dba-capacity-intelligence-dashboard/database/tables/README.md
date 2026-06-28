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
| `009_AlertHistory.sql` | `dbo.AlertHistory` | Stores alerts raised by forecast logic and collector failure handling. |
| `010_LongRunningTransactionHistory.sql` | `dbo.LongRunningTransactionHistory` | Stores open transaction evidence, SQL text, and cached XML query plan when available. |
| `011_TempDBSessionUsageHistory.sql` | `dbo.TempDBSessionUsageHistory` | Stores top session-level TempDB consumers for alert drill-through. |
| `012_BlockingSessionHistory.sql` | `dbo.BlockingSessionHistory` | Stores lead blocker, blocked request, wait, object, SQL text, lock, and cached query plan evidence. |
| `013_AlwaysOnHealthHistory.sql` | `dbo.AlwaysOnHealthHistory` | Stores Always On replica/database synchronization and health evidence. |
| `014_ReplicationHealthHistory.sql` | `dbo.ReplicationHealthHistory` | Stores replication database flags and replication agent status/error evidence. |

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

Common alert types:

```text
CollectionFailure:DatabaseSize
CollectionFailure:FileSize
CollectionFailure:DiskSpace
CapacityRisk
```

The dashboard reads active unresolved rows from `dbo.vw_ActiveAlerts`.

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
