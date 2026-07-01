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
| DBA Capacity - Auto Heal | `auto-heal.yml` | Runs controlled remediation actions requested from alert More info. |
| DBA Capacity - Deploy API | `deploy-api.yml` | Builds and deploys ASP.NET Core API to IIS. |
| DBA Capacity - Deploy Web | `deploy-web.yml` | Builds and deploys React static site to IIS. |

## Shared Assumptions

Current YAMLs target:

```text
Pool: Shamvil-pool
Agent: shamvil
OS: Windows_NT
```

`deploy-api.yml` and `deploy-web.yml` expose queue-time parameters so the job runner and IIS host can be selected without editing YAML:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `iisAgentPool` | `Shamvil-pool` | Self-hosted agent pool containing the agent that runs the deploy job. |
| `iisAgentName` | API: `eve-vsts`; Web: `shamvil` | Agent name that runs the deploy job. |
| `iisDeploymentMode` | `Local` | `Local` runs IIS commands on the selected agent; `Remote` runs IIS commands on `iisHostName` through PowerShell remoting. |
| `iisHostName` | `localhost` | Remote IIS server name or FQDN when `iisDeploymentMode = Remote`. |

For a split automation/IIS topology, select the automation agent with `iisAgentPool`/`iisAgentName`, set `iisDeploymentMode = Remote`, and set `iisHostName` to the IIS web server.

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
| `DBA_API_ALLOWED_ORIGINS` | No | Semicolon-separated dashboard browser origins, for example `https://dba-capacity.contoso.local` or `http://dba-capacity-web`. |
| `AZDO_ORGANIZATION` | No | Azure DevOps organization used by the dashboard Run collector button. |
| `AZDO_PROJECT` | No | Azure DevOps project containing the collector pipeline. |
| `AZDO_COLLECTOR_PIPELINE_ID` | No | Numeric id of `DBA Capacity - Collect Metrics`; preferred when known. |
| `AZDO_COLLECTOR_PIPELINE_NAME` | No | Pipeline name fallback, usually `DBA Capacity - Collect Metrics`. |
| `AZDO_AUTOHEAL_PIPELINE_ID` | No | Numeric id of `DBA Capacity - Auto Heal`; preferred when known. |
| `AZDO_AUTOHEAL_PIPELINE_NAME` | No | Pipeline name fallback, usually `DBA Capacity - Auto Heal`. |
| `AZDO_PAT` | Yes | Automation PAT used by the API to queue and read collector and auto-heal pipeline runs. |
| `IIS_API_*` | No | API IIS settings. |
| `IIS_WEB_*` | No | Web IIS settings. |
| `IIS_REMOTE_USER` | No | Optional account for remote IIS deployment. Leave blank to use the agent service identity. |
| `IIS_REMOTE_PASSWORD` | Yes | Password for `IIS_REMOTE_USER`; leave blank for gMSA/current-identity remoting. |
| `IIS_REMOTE_STAGING_PATH` | No | Remote staging folder, default `C:\Windows\Temp\dba-capacity-deploy`. |
| `IIS_ASPNETCORE_HOSTING_BUNDLE_URL` | No | Optional .NET 9 Windows Hosting Bundle URL override for API IIS hosting. |

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
| `connectionMode` | Authentication protocol: `SqlAuth`, `WindowsAuth`, `AzureADPassword`, or `AzureADIntegrated`. |
| `credentialKey` | Free-text secret lookup key such as `default`, `prod`, `azuresql-sql`, or `azuresql-aad`. |
| `isActive` | Whether the collector should process the server. |

The pipeline performs an upsert into `dbo.ServerInventory`.

`connectionMode` and `credentialKey` are intentionally separate:

- `connectionMode` tells the collector how to authenticate.
- `credentialKey` tells the collector which username/password entry to read from `SOURCE_SQL_CREDENTIALS_JSON`.
- Windows/integrated modes usually do not need a username/password credential key because the collector uses the Windows identity running the agent.
- Add customer-specific keys such as `prod`, `finance-prod`, or `customer-a` directly in `SOURCE_SQL_CREDENTIALS_JSON`, then type the same value in `credentialKey`.

Examples:

| Scenario | `connectionMode` | `credentialKey` |
| --- | --- | --- |
| Local SQL Server using SQL login from default secret | `SqlAuth` | `default` |
| Azure SQL using SQL authentication | `SqlAuth` | `azuresql-sql` |
| Azure SQL using Entra ID username/password | `AzureADPassword` | `azuresql-aad` |
| SQL Server trusted connection from agent service account | `WindowsAuth` | `default` |
| Azure SQL integrated auth from suitable domain/AAD identity | `AzureADIntegrated` | `default` |

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

## Auto Heal

File:

```text
auto-heal.yml
```

What it does:

1. Installs dbatools.
2. Runs `collector/Invoke-AutoHeal.ps1`.
3. Uses the same `configs` repository/source credential variables as the collector.
4. Writes durable request, file-candidate, and action outcome data to `dbo.AutoHealRequest` and `dbo.AutoHealFileCandidate`.

Queue-time actions:

| Action | Purpose |
| --- | --- |
| `BackupRetentionScan` | Scans a target path or latest known source volumes, deletes `.bak`/`.trn` files older than `retentionDays`, and lists remaining files for dashboard selection. |
| `DeleteSelectedBackupFiles` | Deletes only file rows selected in the dashboard from the previous scan. |
| `LogShrinkAssessment` | Attempts log shrink only after open transaction, used percent, log size, and log reuse wait safety checks pass. |

Important runtime parameters:

| Parameter | Purpose |
| --- | --- |
| `requestId` | Repository request id created by the API. Manual runs should not use the all-zero default. |
| `serverName` | Target SQL Server. Manual runs must replace `__REQUIRED__`. |
| `databaseName` | Target database for log shrink. Use `__NONE__` for backup-file cleanup. |
| `backupScanPath` | Optional backup scan path or volume. Use `__AUTO__` to scan latest known source volumes from `DiskSpaceHistory`. |
| `retentionDays` | Age threshold for automatic `.bak`/`.trn` deletion, default `90`. |

Dashboard trigger:

- Alert More info calls the API, not Azure DevOps directly.
- The API uses `AZDO_PAT` plus `AZDO_AUTOHEAL_PIPELINE_ID` or `AZDO_AUTOHEAL_PIPELINE_NAME`.
- The pipeline agent identity must have filesystem permissions to the target backup path or administrative share for backup cleanup.
- Log shrink uses the source server connection mode and credential key from `dbo.ServerInventory`.

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
8. Grants API app pool read access, alert delete access, alert-threshold update access, and CMDB table write access to `DBAUtility` where possible.

Collector and auto-heal trigger settings written by this pipeline:

```text
AZDO_ORGANIZATION
AZDO_PROJECT
AZDO_COLLECTOR_PIPELINE_ID
AZDO_COLLECTOR_PIPELINE_NAME
AZDO_AUTOHEAL_PIPELINE_ID
AZDO_AUTOHEAL_PIPELINE_NAME
AZDO_PAT
```

Create the PAT under a service or automation identity, mark `AZDO_PAT` secret, and grant only pipeline read/run permission needed for `DBA Capacity - Collect Metrics` and `DBA Capacity - Auto Heal`.

In `Local` mode, the selected agent service must run as local administrator on the IIS server. In `Remote` mode, the remoting identity must be local administrator on `iisHostName`.

Queue-time deployment selection:

| Parameter | Purpose |
| --- | --- |
| `iisAgentPool` | Agent pool containing the agent that runs the deploy job. |
| `iisAgentName` | Agent that runs the deploy job. |
| `iisDeploymentMode` | `Local` for IIS-side agent deployment, `Remote` for automation-agent-to-IIS deployment. |
| `iisHostName` | Remote IIS host name when `iisDeploymentMode = Remote`. |

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

Queue-time deployment selection:

| Parameter | Purpose |
| --- | --- |
| `iisAgentPool` | Agent pool containing the agent that runs the deploy job. |
| `iisAgentName` | Agent that runs the deploy job. |
| `iisDeploymentMode` | `Local` for IIS-side agent deployment, `Remote` for automation-agent-to-IIS deployment. |
| `iisHostName` | Remote IIS host name when `iisDeploymentMode = Remote`. |

## Customer Lift-And-Shift Checklist

1. Update automation pipeline pool/demands where needed; use `iisAgentPool`, `iisAgentName`, `iisDeploymentMode`, and `iisHostName` when queueing API/web deploys.
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
