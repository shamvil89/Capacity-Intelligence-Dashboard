# Models

## Purpose

The `Models` folder contains API response DTOs. These classes define the JSON shape returned to the React frontend.

Models should be simple data containers. They should not contain database access logic or business logic.

## Model Inventory

| Model | Used by | Purpose |
| --- | --- | --- |
| `DashboardSummary` | `GET /api/dashboard/summary` | Summary card values for the dashboard. |
| `CapacityDashboardItem` | `GET /api/capacity/databases` | One latest capacity row per database. |
| `DatabaseTrendPoint` | `GET /api/capacity/databases/{serverName}/{databaseName}/trend` | One chart point in database size history. |
| `TopGrowingTableItem` | `GET /api/capacity/top-growing-tables` | One top growing table row. |
| `AlertItem` | `GET /api/alerts/active` | One active alert row. |
| `ServerInventoryItem` | `GET /api/servers` | One active monitored server row. |
| `AlertThresholdSettingItem` | `GET /api/settings/alert-thresholds` | One editable alert threshold row. |
| `UpdateAlertThresholdSettingRequest` | `PUT /api/settings/alert-thresholds/{settingId}` | Request body for updating one threshold value. |
| `ApplicationCmdbEntryItem` | `GET /api/cmdb/applications` | One application CMDB row with optional database mapping. |
| `UpsertApplicationCmdbRequest` | `PUT /api/cmdb/applications` | Request body for creating/updating application CMDB rows. |
| `BulkUpsertApplicationCmdbRequest` | `POST /api/cmdb/applications/import` | Bulk wrapper for CSV import rows. |

## DashboardSummary

Fields:

| Field | Meaning |
| --- | --- |
| `TotalServers` | Count of active inventory servers. |
| `TotalDatabases` | Count of rows in latest capacity dashboard view. |
| `CriticalAlerts` | Count of active critical alerts. |
| `HighRiskDatabases` | Count of high-risk database rows. |
| `LargestDatabaseName` | Largest database label as `server/database`. |
| `FastestGrowingDatabaseName` | Fastest growing database label as `server/database`. |

## CapacityDashboardItem

Represents one database in the main dashboard.

Fields include:

- Server name
- Database name
- Current size GB
- 7-day, 30-day, and 90-day growth
- Average growth per day
- Available space
- Estimated days remaining
- Risk level
- Recommendation
- Calculation time

## DatabaseTrendPoint

Represents one time-series point for the database detail chart.

Fields:

- Collection time
- Server name
- Database name
- Total size GB
- Data size GB
- Log size GB

## TopGrowingTableItem

Represents table growth.

Fields:

- Server name
- Database name
- Schema name
- Table name
- Current size MB
- 30-day growth MB
- Current row count
- 30-day row growth

## AlertItem

Represents one unresolved alert.

Fields:

- Alert time
- Server name
- Optional database name
- Alert type
- Severity
- Message

Alert types can include forecast alerts and collector failure alerts such as:

```text
CollectionFailure:DatabaseSize
CollectionFailure:FileSize
```

## ServerInventoryItem

Represents one active server inventory row.

Fields:

- Server ID
- Server name
- Environment
- Server type
- Connection mode

The API intentionally does not expose source passwords or `SOURCE_SQL_CREDENTIALS_JSON`.

## AlertThresholdSettingItem

Represents one row from `dbo.AlertThresholdSetting`.

Fields include:

- Alert type and setting key.
- Display name, description, and unit.
- Current value and default value.
- Optional minimum and maximum values.
- Sort order and last update metadata.

The frontend groups these rows by alert type on the Settings page.

## ApplicationCmdbEntryItem

Represents one application CMDB row. If the application has multiple database mappings, the API returns one row per mapping.

Fields include:

- Application id and optional mapping id.
- Application name.
- Optional environment, server, and database mapping fields.
- Optional contact fields: ProdOps, application owner, business owner, support DL, and escalation DL.
- Optional ServiceNow group, criticality, application URL, and notes.
- Last update metadata.

## Dapper Mapping

`Program.cs` enables:

```csharp
Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;
```

Services still alias SQL columns explicitly, for example:

```sql
server_name AS ServerName
```

This keeps DTO mapping predictable.

## Customer Lift-And-Shift Notes

Models usually change only when:

- A new dashboard field is added.
- A SQL view returns a new column.
- The frontend needs a new value.
- A customer-specific report is added.

When changing a model:

1. Update the SQL query in the service.
2. Update the DTO.
3. Update the frontend API usage.
4. Validate Swagger output.

