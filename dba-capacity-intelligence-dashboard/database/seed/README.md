# Database Seed Scripts

## Purpose

The `database/seed` folder contains optional scripts that insert initial data into `DBAUtility`.

Seed scripts are useful for local development and first-time setup, but customer environments usually onboard servers through the onboarding pipeline instead.

## Current Seed Script

| Script | Purpose |
| --- | --- |
| `001_Seed_ServerInventory.sql` | Adds an initial `dbo.ServerInventory` row for local testing. |

## When To Use Seed Scripts

Use seed scripts when:

- Building a local development environment.
- Demonstrating the dashboard quickly.
- Creating a known starter inventory row.

Avoid using seed scripts as the long-term customer inventory process. For customer environments, prefer:

```text
pipelines/onboard-server.yml
```

The onboarding pipeline is repeatable, parameterized, and updates existing rows safely.

## Customer Onboarding Recommendation

Use the pipeline for each customer source:

```text
DBA Capacity - Onboard Server
```

Example parameters:

```text
serverName = customer-sql-01
environment = Production
serverType = SQLServer
connectionMode = SqlAuth
credentialKey = prod
isActive = true
```

Azure SQL example:

```text
serverName = customer.database.windows.net
environment = Production
serverType = AzureSQL
connectionMode = SqlAuth
credentialKey = azuresql
isActive = true
```

## Validation

```sql
SELECT server_name, environment, server_type, connection_mode, credential_key, is_active
FROM DBAUtility.dbo.ServerInventory
ORDER BY server_name;
```

