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
- IIS with Management Scripts and Tools.
- ASP.NET Core Hosting Bundle for IIS API hosting.
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

Health check:

```text
http://localhost:5088/health
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

- `GET /`
- `GET /health`
- `GET /api/dashboard/summary`
- `GET /api/capacity/databases`
- `GET /api/capacity/databases/{serverName}/{databaseName}/trend?days=90`
- `GET /api/capacity/top-growing-tables?limit=20`
- `GET /api/alerts/active`
- `GET /api/servers`

## Azure DevOps Pipelines

- `pipelines/collect-capacity.yml`: scheduled collector run, manual run supported.
- `pipelines/deploy-database.yml`: deploys database scripts in order.
- `pipelines/deploy-api.yml`: restores, builds, tests if present, publishes artifact, and deploys the API to IIS.
- `pipelines/deploy-web.yml`: installs npm packages, builds React, publishes artifact, and deploys the static web app to IIS.

The YAMLs target the self-hosted Windows agent:

```text
Pool: Shamvil-pool
Agent: shamvil
Local path: C:\Users\shamvil\PersonalEnvironment\agent
```

PowerShell pipeline tasks are configured for Windows PowerShell on this host.

The YAMLs use `projectRoot: dba-capacity-intelligence-dashboard` because the project currently lives inside that folder in the repository checkout. If the project files are moved to the repository root, change `projectRoot` to `.` in each pipeline.

All pipeline YAMLs import the Azure DevOps variable group named `configs`. Create these variables in that group and mark secrets as secret.

- `DBA_REPOSITORY_SERVER`
- `DBA_REPOSITORY_DB`
- `DBA_SQL_AUTH_MODE`
- `SQL_USER`
- `SQL_PASSWORD`
- `VITE_API_BASE_URL`
- `IIS_API_SITE_NAME`
- `IIS_API_APP_POOL`
- `IIS_API_PHYSICAL_PATH`
- `IIS_API_PORT`
- `IIS_WEB_SITE_NAME`
- `IIS_WEB_APP_POOL`
- `IIS_WEB_PHYSICAL_PATH`
- `IIS_WEB_PORT`
- `DBA_API_CONNECTION_STRING`
- `DBA_API_ALLOWED_ORIGINS`

For the local default SQL Server instance on the self-hosted agent, set:

```text
DBA_REPOSITORY_SERVER = localhost
DBA_SQL_AUTH_MODE = WindowsAuth
```

Use `DBA_SQL_AUTH_MODE = SqlAuth` if deploying with a SQL login, and provide `SQL_USER` and `SQL_PASSWORD`.

## IIS Deployment Defaults

The API pipeline defaults to:

```text
IIS_API_SITE_NAME = DBA Capacity API
IIS_API_APP_POOL = DBACapacityApi
IIS_API_PHYSICAL_PATH = C:\inetpub\dba-capacity-api
IIS_API_PORT = 5088
```

The web pipeline defaults to:

```text
IIS_WEB_SITE_NAME = DBA Capacity Dashboard
IIS_WEB_APP_POOL = DBACapacityWeb
IIS_WEB_PHYSICAL_PATH = C:\inetpub\dba-capacity-web
IIS_WEB_PORT = 8080
VITE_API_BASE_URL = http://localhost:5088/api
DBA_API_ALLOWED_ORIGINS = http://localhost:8080;http://127.0.0.1:8080
```

The Azure DevOps agent process must run as a local administrator to create IIS sites and app pools. The API deploy pipeline grants `db_datareader` on `DBAUtility` to `IIS APPPOOL\DBACapacityApi` when the repository SQL variables are configured.

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
