# Architecture

The DBA Capacity Intelligence Dashboard is centered on a DBAUtility repository database. Source SQL Servers are monitored by a scheduled Azure DevOps collector pipeline, and the web application reads only from the central repository through the API.

```text
Source SQL Servers
        |
Scheduled Azure DevOps Collector Pipeline
        |
PowerShell Collector Scripts
        |
Central DBAUtility Database
        |
Forecast Stored Procedures
        |
ASP.NET Core Web API
        |
React Dashboard Web App
```

## Components

- `database/` contains idempotent SQL Server scripts for DBAUtility tables, insert procedures, forecast procedures, alert procedures, views, and seed data.
- `collector/` contains PowerShell scripts that use dbatools to query active servers from `dbo.ServerInventory`, collect metrics, and write rows to DBAUtility.
- `api/DBA.Capacity.Api/` exposes dashboard endpoints over DBAUtility using Dapper and supports deleting selected alert rows.
- `web/dba-capacity-web/` provides the React admin dashboard.
- `pipelines/` contains Azure DevOps YAMLs for collection, database deployment, API build, and web build.

## Data Flow

1. `collect-capacity.yml` runs on a schedule or manually.
2. `Collect-CapacityMetrics.ps1` reads active SQL Servers from `dbo.ServerInventory`.
3. Metric scripts collect database, file, disk, table, backup, and TempDB data.
4. Insert stored procedures write history rows to DBAUtility.
5. `usp_GenerateCapacityForecast` creates latest capacity risk calculations.
6. `usp_GenerateAlerts` inserts active alerts without duplicating same-day alerts.
7. The API reads only from DBAUtility tables and views.
8. The React app calls the API and never receives SQL credentials.

## Security Boundary

The frontend never connects to SQL Server. The API connection string stays server-side, and collector credentials are passed through environment variables or Azure DevOps secret variables. Future production deployments should use Entra ID, Managed Identity, Key Vault, and role-based authorization.
