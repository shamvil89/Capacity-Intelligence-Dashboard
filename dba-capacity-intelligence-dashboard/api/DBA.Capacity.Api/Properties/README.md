# Properties

## Purpose

The `Properties` folder contains development-time launch settings for the API project.

These settings are used when running the API locally with `dotnet run` or from an IDE. They are not the source of truth for IIS production deployment.

## File

| File | Purpose |
| --- | --- |
| `launchSettings.json` | Defines the local `http` launch profile. |

## Current Launch Profile

Profile name:

```text
http
```

Local URL:

```text
http://localhost:5088
```

Launch URL:

```text
swagger
```

Environment:

```text
ASPNETCORE_ENVIRONMENT = Development
```

## Local Run

```powershell
dotnet run --project .\api\DBA.Capacity.Api\DBA.Capacity.Api.csproj --launch-profile http
```

Expected result:

```text
http://localhost:5088/swagger
```

## Difference Between Local And IIS

| Area | Local launch profile | IIS deployment |
| --- | --- | --- |
| URL | `http://localhost:5088` | Controlled by `IIS_API_PORT` and IIS binding. |
| Environment | `Development` | Usually `Production`. |
| Settings | `appsettings.json` and `appsettings.Development.json` | `appsettings.json` and generated `appsettings.Production.json`. |
| Process | `dotnet run` | IIS ASP.NET Core Module. |

## Customer Lift-And-Shift Notes

Customer deployments rarely need to edit `launchSettings.json`. It is useful only for local development or debugging on an engineer workstation.

For customer IIS deployments, change Azure DevOps variables instead:

- `IIS_API_SITE_NAME`
- `IIS_API_APP_POOL`
- `IIS_API_PHYSICAL_PATH`
- `IIS_API_PORT`
- `DBA_API_CONNECTION_STRING`
- `DBA_API_ALLOWED_ORIGINS`

