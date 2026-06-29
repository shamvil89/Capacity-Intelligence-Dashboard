# DBA Capacity Intelligence Dashboard

DBA Capacity Intelligence Dashboard is an MVP DBA automation system for collecting SQL Server capacity metrics into a central `DBAUtility` repository, generating growth forecasts, and exposing a secure dashboard through an ASP.NET Core API and React frontend.

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
- `DELETE /api/alerts/{alertId}`
- `GET /api/servers`
- `GET /api/collector-run`
- `POST /api/collector-run`

`POST /api/collector-run` lets the dashboard trigger the `DBA Capacity - Collect Metrics` Azure DevOps pipeline through the API. The browser never receives the Azure DevOps PAT. The API queues the pipeline using server-side configuration, then `GET /api/collector-run` polls the latest run so the dashboard button can stay disabled until Azure DevOps reports that the run is complete.

## Azure DevOps Pipelines

- `pipelines/collect-capacity.yml`: scheduled collector run, manual run supported.
- `pipelines/onboard-server.yml`: manually adds or updates a row in `dbo.ServerInventory`.
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
- `SOURCE_SQL_CREDENTIALS_JSON`
- `VITE_API_BASE_URL`
- `IIS_API_SITE_NAME`
- `IIS_API_APP_POOL`
- `IIS_API_PHYSICAL_PATH`
- `IIS_API_PORT`
- `IIS_WEB_SITE_NAME`
- `IIS_WEB_APP_POOL`
- `IIS_WEB_PHYSICAL_PATH`
- `IIS_WEB_PORT`
- `IIS_REMOTE_USER`
- `IIS_REMOTE_PASSWORD`
- `IIS_REMOTE_STAGING_PATH`
- `IIS_ASPNETCORE_HOSTING_BUNDLE_URL`
- `DBA_API_CONNECTION_STRING`
- `DBA_API_ALLOWED_ORIGINS`
- `AZDO_ORGANIZATION`
- `AZDO_PROJECT`
- `AZDO_COLLECTOR_PIPELINE_ID`
- `AZDO_COLLECTOR_PIPELINE_NAME`
- `AZDO_PAT`

For the local default SQL Server instance on the self-hosted agent, set:

```text
DBA_REPOSITORY_SERVER = .
DBA_SQL_AUTH_MODE = WindowsAuth
```

Use `.` instead of `localhost` for local Windows authentication from the agent service. `localhost` can be treated as a network connection and may appear to SQL Server as an unresolvable workgroup machine account.

Use `DBA_SQL_AUTH_MODE = SqlAuth` if deploying with a SQL login, and provide `SQL_USER` and `SQL_PASSWORD`.

For the dashboard Run collector button, add these variables to `configs`:

```text
AZDO_ORGANIZATION = kaz-tec
AZDO_PROJECT = PersonalEnvironment
AZDO_COLLECTOR_PIPELINE_NAME = DBA Capacity - Collect Metrics
AZDO_COLLECTOR_PIPELINE_ID = optional numeric pipeline id
AZDO_PAT = secret PAT owned by an automation account
```

Mark `AZDO_PAT` as secret. The PAT only needs permission to read and run pipelines. Prefer using `AZDO_COLLECTOR_PIPELINE_ID` when available because it avoids ambiguity if multiple pipelines share similar names.

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

For customer deployments, set `DBA_API_ALLOWED_ORIGINS` to the dashboard server name or DNS alias that users open in the browser, for example:

```text
DBA_API_ALLOWED_ORIGINS = https://dba-capacity.contoso.local
DBA_API_ALLOWED_ORIGINS = http://dba-capacity-web
```

Only include a port when the web IIS binding uses a non-standard port, such as `http://dba-capacity-web:8080`.

The deploy pipelines support two IIS deployment modes. Use `iisDeploymentMode = Local` when the selected Azure DevOps agent is installed on the IIS server. Use `iisDeploymentMode = Remote` when the selected agent is on a separate automation server and should deploy to `iisHostName` over PowerShell remoting.

For local mode, the Azure DevOps agent process must run as a local administrator to create IIS sites and app pools. For remote mode, the remoting identity must be local administrator on the IIS host; set `IIS_REMOTE_USER` and secret `IIS_REMOTE_PASSWORD` only when you do not want to use the agent service identity. For gMSA/current-identity remoting, leave both remote credential variables empty.

The API deploy pipeline also verifies the ASP.NET Core IIS module and installs or repairs the .NET 9 Windows Hosting Bundle when it is missing. By default it downloads from `https://aka.ms/dotnet/9.0/dotnet-hosting-win.exe`; set `IIS_ASPNETCORE_HOSTING_BUNDLE_URL` if the customer requires an internal software mirror.

The API deploy pipeline grants `db_datareader` plus `DELETE` on `dbo.AlertHistory` to `IIS APPPOOL\DBACapacityApi` in local mode when the repository SQL variables are configured. Remote mode skips that virtual-account grant because `IIS APPPOOL\...` is local to the remote IIS server; use `DBA_API_CONNECTION_STRING` with a SQL/domain credential or manually grant the remote app pool/domain identity in SQL Server.

Azure SQL Database inventory rows should use `server_type = AzureSQL`. Disk, backup, and TempDB collectors are skipped for Azure SQL Database because those metrics depend on instance-level SQL Server DMVs.

Source server credentials can vary by server. Store source credentials in the `configs` variable group as a secret named `SOURCE_SQL_CREDENTIALS_JSON`:

```json
{"default":{"user":"sa","password":"local-source-password"},"azuresql-sql":{"user":"azure_sql_admin","password":"azure-source-password"},"azuresql-aad":{"user":"dba.user@contoso.com","password":"entra-id-password"}}
```

Supported source `connection_mode` values:

- `SqlAuth`: uses `SOURCE_SQL_CREDENTIALS_JSON` or `SQL_USER`/`SQL_PASSWORD` for `credential_key = default`.
- `WindowsAuth`: uses the Windows identity running the collector process or Azure DevOps agent service.
- `AzureADPassword`: uses an Entra ID user/password from `SOURCE_SQL_CREDENTIALS_JSON`.
- `AzureADIntegrated`: uses the signed-in/domain/AAD-joined Windows identity running the collector process.
- `ManagedIdentity`: reserved for a future Microsoft.Data.SqlClient token-based collector path.

For SQL auth Azure SQL, use `connection_mode = SqlAuth` and `credential_key = azuresql-sql`. For Entra ID password auth, use `connection_mode = AzureADPassword` and `credential_key = azuresql-aad`. For trusted Windows SQL Server auth, use `connection_mode = WindowsAuth` and run the agent service as the Windows or domain account that SQL Server trusts.

`connection_mode` chooses the authentication method. `credential_key` chooses which secret entry to read from `SOURCE_SQL_CREDENTIALS_JSON`; it can be any customer-defined key such as `default`, `prod`, `finance-prod`, `azuresql-sql`, or `azuresql-aad`.

The API and web deploy pipelines expose queue-time `iisAgentPool`, `iisAgentName`, `iisDeploymentMode`, and `iisHostName` parameters. `iisAgentPool`/`iisAgentName` choose the agent that runs the job. `iisHostName` is only used in remote mode and points to the IIS server.

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
- `docs/customer-lift-and-shift-wiki.md`
- `docs/screenshots.md`
