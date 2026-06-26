# Setup Guide

## Prerequisites

- SQL Server 2019 or newer for the DBAUtility repository.
- SQL Server permissions to create databases, tables, procedures, and views.
- PowerShell 7 or Windows PowerShell 5.1.
- .NET SDK 9.
- Node.js 22 or newer.
- IIS with Management Scripts and Tools.
- ASP.NET Core Hosting Bundle for IIS API hosting.
- Azure DevOps pipeline access for scheduled collection.

## Database Setup

Run the SQL scripts in this order:

1. `database/001_Create_Database.sql`
2. `database/tables/*.sql`
3. `database/procedures/*.sql`
4. `database/views/*.sql`
5. `database/seed/*.sql`

The `pipelines/deploy-database.yml` file performs the same order automatically.

## Onboard A Server By Pipeline

Use `pipelines/onboard-server.yml` to add or update one `dbo.ServerInventory` row from Azure DevOps.

Default queue-time parameters match the local development server:

```text
serverName = DESKTOP-CIS3NI4
environment = Development
serverType = SQLServer
connectionMode = SqlAuth
isActive = true
```

After onboarding, run `pipelines/collect-capacity.yml` to collect metrics for active servers.

If `DBA_SQL_AUTH_MODE = WindowsAuth`, SQL Server must allow the Azure DevOps agent identity to write to `dbo.ServerInventory`. The pipeline prints the identity as `Pipeline Windows identity`. Grant that identity access or use `SqlAuth`.

## Seed Server Inventory

Update `dbo.ServerInventory` with active SQL Server instances:

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

## Local Collector Run

Set the required environment variables:

```powershell
$env:DBA_REPOSITORY_SERVER = "localhost"
$env:DBA_REPOSITORY_DB = "DBAUtility"
$env:SQL_USER = "collector_login"
$env:SQL_PASSWORD = "your-password"

.\collector\Collect-CapacityMetrics.ps1
```

## Local API Run

```powershell
dotnet run --project .\api\DBA.Capacity.Api\DBA.Capacity.Api.csproj --launch-profile http
```

Swagger opens at:

```text
http://localhost:5088/swagger
```

Health check:

```text
http://localhost:5088/health
```

## Local Web Run

```powershell
cd .\web\dba-capacity-web
npm install
$env:VITE_API_BASE_URL = "http://localhost:5088/api"
npm run dev
```

The app runs at:

```text
http://localhost:5173
```

## Azure DevOps Variables

The pipeline YAMLs are configured to run on the self-hosted Azure DevOps agent at `C:\Users\shamvil\PersonalEnvironment\agent`:

```text
Pool: Shamvil-pool
Agent: shamvil
Service: vstsagent.kaz-tec.Shamvil-pool.shamvil
Organization: https://dev.azure.com/kaz-tec/
```

The agent currently uses Windows PowerShell for `PowerShell@2` tasks because `pwsh` is not installed on the host.

The YAMLs assume the project folder is checked out as `$(Build.SourcesDirectory)\dba-capacity-intelligence-dashboard`. If you later move the contents of that folder to the repository root, update the `projectRoot` variable in each pipeline to `.`.

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

The scheduled collector uses Azure DevOps cron in UTC. Adjust `pipelines/collect-capacity.yml` if your desired 2:30 AM run should follow a local timezone.

For the local default SQL Server instance on the self-hosted agent machine, use:

```text
DBA_REPOSITORY_SERVER = localhost
DBA_SQL_AUTH_MODE = WindowsAuth
```

Use `DBA_SQL_AUTH_MODE = SqlAuth` when deploying with a SQL login. In that case, `SQL_USER` and `SQL_PASSWORD` are required.

## IIS Deployment

The API pipeline creates or updates this site by default:

```text
Site: DBA Capacity API
App pool: DBACapacityApi
Path: C:\inetpub\dba-capacity-api
URL: http://localhost:5088
```

The web pipeline creates or updates this site by default:

```text
Site: DBA Capacity Dashboard
App pool: DBACapacityWeb
Path: C:\inetpub\dba-capacity-web
URL: http://localhost:8080
```

Set this value in the `configs` variable group before building the web app:

```text
VITE_API_BASE_URL = http://localhost:5088/api
```

Set this API CORS value if the web URL changes:

```text
DBA_API_ALLOWED_ORIGINS = http://localhost:8080;http://127.0.0.1:8080
```

The Azure DevOps agent process must run as a local administrator to create IIS sites and app pools.

For the API database connection, choose one of these options:

1. Let `deploy-api.yml` grant SQL Server access to the IIS app pool identity `IIS APPPOOL\DBACapacityApi`.
2. Set `DBA_API_CONNECTION_STRING` in the `configs` variable group. Example:

```text
Server=localhost;Database=DBAUtility;Trusted_Connection=True;TrustServerCertificate=True;
```
