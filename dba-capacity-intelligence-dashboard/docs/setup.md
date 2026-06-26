# Setup Guide

## Prerequisites

- SQL Server 2019 or newer for the DBAUtility repository.
- SQL Server permissions to create databases, tables, procedures, and views.
- PowerShell 7 or Windows PowerShell 5.1.
- .NET SDK 9.
- Node.js 22 or newer.
- Azure DevOps pipeline access for scheduled collection.

## Database Setup

Run the SQL scripts in this order:

1. `database/001_Create_Database.sql`
2. `database/tables/*.sql`
3. `database/procedures/*.sql`
4. `database/views/*.sql`
5. `database/seed/*.sql`

The `pipelines/deploy-database.yml` file performs the same order automatically.

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

Create these variables in the pipeline or variable group. Mark secrets as secret.

- `DBA_REPOSITORY_SERVER`
- `DBA_REPOSITORY_DB`
- `DBA_SQL_AUTH_MODE`
- `SQL_USER`
- `SQL_PASSWORD`
- `VITE_API_BASE_URL`

The scheduled collector uses Azure DevOps cron in UTC. Adjust `pipelines/collect-capacity.yml` if your desired 2:30 AM run should follow a local timezone.

For the local default SQL Server instance on the self-hosted agent machine, use:

```text
DBA_REPOSITORY_SERVER = localhost
DBA_SQL_AUTH_MODE = WindowsAuth
```

Use `DBA_SQL_AUTH_MODE = SqlAuth` when deploying with a SQL login. In that case, `SQL_USER` and `SQL_PASSWORD` are required.
