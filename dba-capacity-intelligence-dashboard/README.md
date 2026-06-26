# DBA Capacity Intelligence Dashboard

DBA Capacity Intelligence Dashboard is an MVP DBA automation system for collecting SQL Server capacity metrics into a central `DBAUtility` repository, generating growth forecasts, and exposing a secure read-only dashboard through an ASP.NET Core API and React frontend.

```text
Source SQL Servers
        |
Scheduled Azure DevOps Collector Pipeline
        |
PowerShell Collector Script
        |
Central DBAUtility Database
        |
Forecast Stored Procedures
        |
ASP.NET Core Web API
        |
React Dashboard Web App
```

## What Is Included

- SQL Server repository scripts for tables, procedures, forecast logic, alerts, views, and seed data.
- PowerShell collectors for database size, file size, disk space, table size, backup size, and TempDB usage.
- ASP.NET Core Web API with Dapper, Swagger, CORS, and error handling middleware.
- React Vite admin dashboard with summary cards, filtering, detail chart, top tables, and alerts.
- Azure DevOps YAMLs for collection and build/deployment workflows.
- Setup and architecture documentation.

## Prerequisites

- SQL Server 2019 or newer.
- PowerShell 7 or Windows PowerShell 5.1.
- .NET SDK 9.
- Node.js 22 or newer.
- Azure DevOps for scheduled collector automation.

## Database Setup

Run scripts in this order:

```text
database/001_Create_Database.sql
database/tables/*.sql
database/procedures/*.sql
database/views/*.sql
database/seed/*.sql
```

The database deployment pipeline runs the same order automatically:

```text
pipelines/deploy-database.yml
```

## Seed Server Inventory

Add monitored SQL Servers to `dbo.ServerInventory` and set `is_active = 1`.

```sql
INSERT INTO dbo.ServerInventory
(
    server_name,
    environment,
    server_type,
    connection_mode,
    is_active
)
VALUES
(
    N'prod-sql-01.example.net',
    'Production',
    'SQLServer',
    'SqlAuth',
    1
);
```

## Run Collector Locally

```powershell
$env:DBA_REPOSITORY_SERVER = "localhost"
$env:DBA_REPOSITORY_DB = "DBAUtility"
$env:SQL_USER = "collector_login"
$env:SQL_PASSWORD = "your-password"

.\collector\Collect-CapacityMetrics.ps1
```

The collector installs `dbatools` for the current user if it is missing. Logs are written to `collector/logs/`.

## Run API Locally

```powershell
dotnet run --project .\api\DBA.Capacity.Api\DBA.Capacity.Api.csproj --launch-profile http
```

Swagger:

```text
http://localhost:5088/swagger
```

The default local connection string is in `api/DBA.Capacity.Api/appsettings.json`.

## Run React App Locally

```powershell
cd .\web\dba-capacity-web
npm install
$env:VITE_API_BASE_URL = "http://localhost:5088/api"
npm run dev
```

Open:

```text
http://localhost:5173
```

## API Endpoints

- `GET /api/dashboard/summary`
- `GET /api/capacity/databases`
- `GET /api/capacity/databases/{serverName}/{databaseName}/trend?days=90`
- `GET /api/capacity/top-growing-tables?limit=20`
- `GET /api/alerts/active`
- `GET /api/servers`

## Azure DevOps Pipelines

- `pipelines/collect-capacity.yml`: scheduled collector run, manual run supported.
- `pipelines/deploy-database.yml`: deploys database scripts in order.
- `pipelines/deploy-api.yml`: restores, builds, tests if present, and publishes API artifact.
- `pipelines/deploy-web.yml`: installs npm packages, builds React, and publishes web artifact.

The YAMLs target the self-hosted Windows agent:

```text
Pool: Shamvil-pool
Agent: shamvil
Local path: C:\Users\shamvil\PersonalEnvironment\agent
```

PowerShell pipeline tasks are configured for Windows PowerShell on this host.

The YAMLs use `projectRoot: dba-capacity-intelligence-dashboard` because the project currently lives inside that folder in the repository checkout. If the project files are moved to the repository root, change `projectRoot` to `.` in each pipeline.

Create these variables in Azure DevOps. Mark secrets as secret.

- `DBA_REPOSITORY_SERVER`
- `DBA_REPOSITORY_DB`
- `SQL_USER`
- `SQL_PASSWORD`
- `VITE_API_BASE_URL`

## Security Notes

- The web app never connects directly to production SQL Servers.
- The API reads only from the central DBAUtility database.
- SQL credentials are not committed to Git.
- Use pipeline secret variables for collector credentials.
- TODO: Add Azure AD / Entra ID authentication.
- TODO: Add role-based access.
- TODO: Use Managed Identity.
- TODO: Store secrets in Key Vault.

## MVP Limitations

- SQL authentication is used for the MVP collector path.
- Disk-space-to-database mapping is conservative and server-level.
- Forecasting uses simple historical deltas rather than seasonal modeling.
- Alert thresholds are intentionally simple and should be tuned per estate.
- No authentication is enforced yet in the API or frontend.

## Future Enhancements

- Azure AD login
- Teams alerts
- Email alerts
- ServiceNow/Jira ticket creation
- Azure SQL auto-scale after manual approval
- Query Store regression dashboard
- Backup restore validation dashboard
- DBCC CHECKDB result tracking
- Always On availability group health page

## More Documentation

- `docs/architecture.md`
- `docs/setup.md`
- `docs/screenshots-placeholder.md`
