# Pipelines

## Purpose

The `pipelines` folder contains Azure DevOps YAML definitions for deploying and operating the DBA Capacity Intelligence Dashboard.

Each pipeline is intentionally focused on one operational job.

## Pipeline Inventory

| Pipeline | YAML file | Purpose |
| --- | --- | --- |
| DBA Capacity - Deploy Database | `deploy-database.yml` | Deploys `DBAUtility` database scripts. |
| DBA Capacity - Onboard Server | `onboard-server.yml` | Adds or updates one server inventory row. |
| DBA Capacity - Collect Metrics | `collect-capacity.yml` | Runs collectors and publishes logs. |
| DBA Capacity - Deploy API | `deploy-api.yml` | Builds and deploys ASP.NET Core API to IIS. |
| DBA Capacity - Deploy Web | `deploy-web.yml` | Builds and deploys React static site to IIS. |

## Shared Assumptions

Current YAMLs target:

```text
Pool: Shamvil-pool
Agent: shamvil
OS: Windows_NT
```

All pipelines import the Azure DevOps variable group:

```text
configs
```

Current project root:

```yaml
- name: projectRoot
  value: dba-capacity-intelligence-dashboard
```

If the customer repo stores project files at repository root, change this value to:

```yaml
value: .
```

## Variable Group

Required group:

```text
configs
```

Important variables:

| Variable | Secret | Purpose |
| --- | --- | --- |
| `DBA_REPOSITORY_SERVER` | No | SQL Server hosting `DBAUtility`. |
| `DBA_REPOSITORY_DB` | No | Repository database name. |
| `DBA_SQL_AUTH_MODE` | No | Repository auth mode, `SqlAuth` or `WindowsAuth`. |
| `SQL_USER` | Yes | Repository SQL login or fallback source login. |
| `SQL_PASSWORD` | Yes | Password for `SQL_USER`. |
| `SOURCE_SQL_CREDENTIALS_JSON` | Yes | Source credential key map. |
| `VITE_API_BASE_URL` | No | API URL compiled into React app. |
| `DBA_API_CONNECTION_STRING` | Yes | API connection string. |
| `DBA_API_ALLOWED_ORIGINS` | No | Semicolon-separated CORS origins. |
| `AZDO_ORGANIZATION` | No | Azure DevOps organization used by the dashboard Run collector button. |
| `AZDO_PROJECT` | No | Azure DevOps project containing the collector pipeline. |
| `AZDO_COLLECTOR_PIPELINE_ID` | No | Numeric id of `DBA Capacity - Collect Metrics`; preferred when known. |
| `AZDO_COLLECTOR_PIPELINE_NAME` | No | Pipeline name fallback, usually `DBA Capacity - Collect Metrics`. |
| `AZDO_PAT` | Yes | Automation PAT used by the API to queue and read collector pipeline runs. |
| `IIS_API_*` | No | API IIS settings. |
| `IIS_WEB_*` | No | Web IIS settings. |

## Deploy Database

File:

```text
deploy-database.yml
```

What it does:

1. Installs the SqlServer PowerShell module.
2. Connects to the repository SQL Server.
3. Runs scripts in database deployment order.
4. Fails fast if required variables are missing.

Run this first in every new customer environment.

## Onboard Server

File:

```text
onboard-server.yml
```

Queue-time parameters:

| Parameter | Purpose |
| --- | --- |
| `serverName` | Source server or Azure SQL logical server. |
| `environment` | Development, Test, QA, UAT, Production, or DR. |
| `serverType` | `SQLServer`, `AzureSQL`, or `ManagedInstance`. |
| `connectionMode` | `SqlAuth`, `WindowsAuth`, or `ManagedIdentity`. |
| `credentialKey` | Source credential key. |
| `isActive` | Whether the collector should process the server. |

The pipeline performs an upsert into `dbo.ServerInventory`.

## Collect Metrics

File:

```text
collect-capacity.yml
```

What it does:

1. Installs dbatools.
2. Runs `collector/Collect-CapacityMetrics.ps1`.
3. Passes repository and source credential variables.
4. Publishes `collector-logs`.

Schedule:

```yaml
cron: "*/10 * * * *"
```

Azure DevOps cron is UTC. For production, consider `*/15` or a customer-approved interval.

Dashboard trigger:

- The dashboard Run collector button calls the API, not Azure DevOps directly.
- The API uses `AZDO_PAT` from `appsettings.Production.json` written by `deploy-api.yml`.
- The button polls `GET /api/collector-run` and becomes clickable again after Azure DevOps reports the run state as `completed`.
- Dashboard users do not need Azure DevOps pipeline permissions because the API is the controlled trigger boundary.

## Deploy API

File:

```text
deploy-api.yml
```

What it does:

1. Installs .NET SDK.
2. Restores packages.
3. Builds API.
4. Runs tests if present.
5. Publishes API artifact.
6. Deploys to IIS.
7. Writes production appsettings if configured.
8. Grants API app pool read access to `DBAUtility` where possible.

Collector trigger settings written by this pipeline:

```text
AZDO_ORGANIZATION
AZDO_PROJECT
AZDO_COLLECTOR_PIPELINE_ID
AZDO_COLLECTOR_PIPELINE_NAME
AZDO_PAT
```

Create the PAT under a service or automation identity, mark `AZDO_PAT` secret, and grant only pipeline read/run permission needed for `DBA Capacity - Collect Metrics`.

The agent service must run as a local administrator.

## Deploy Web

File:

```text
deploy-web.yml
```

What it does:

1. Installs Node.js 22.
2. Runs `npm ci`.
3. Builds the Vite React app.
4. Publishes the `dist` artifact.
5. Deploys static files to IIS.

The web app is static. The API URL is compiled at build time using `VITE_API_BASE_URL`.

## Customer Lift-And-Shift Checklist

1. Update agent pool and demands in all YAML files.
2. Update `projectRoot` if repository layout changes.
3. Create variable group `configs`.
4. Mark passwords and connection strings secret.
5. Run Deploy Database.
6. Onboard source servers.
7. Run Collect Metrics manually once.
8. Deploy API.
9. Deploy Web.
10. Confirm scheduled collection.

## Common Pipeline Failures

| Failure | Cause | Fix |
| --- | --- | --- |
| Path not found under `$(Build.SourcesDirectory)` | Wrong `projectRoot`. | Set `projectRoot` to correct folder or `.`. |
| IIS deployment requires Administrator | Agent service is not local admin. | Run agent as dedicated local admin account. |
| Login failed for `WORKGROUP\...$` | Windows auth through service identity. | Use `.` for local SQL or switch repository to SQL auth. |
| Scheduled runs do not fire | Branch filter mismatch or UI schedules override YAML. | Include active branch and remove UI schedules. |
| Web calls wrong API URL | `VITE_API_BASE_URL` was wrong at build time. | Fix variable and rebuild web. |
