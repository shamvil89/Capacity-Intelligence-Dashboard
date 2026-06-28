# Web

## Purpose

The `web` folder contains the React dashboard that users open in the browser. It is a static Vite application deployed to IIS.

The web app calls the ASP.NET Core API and never connects directly to SQL Server.

## Project Location

```text
web/dba-capacity-web
```

## Runtime Stack

| Area | Technology |
| --- | --- |
| Framework | React |
| Build tool | Vite |
| Routing | React Router HashRouter |
| Charts | Recharts |
| Icons | Lucide React |
| Query plans | `html-query-plan` |
| Hosting | IIS static site |
| Pipeline | `pipelines/deploy-web.yml` |

## App Pages

| Page | Route | Purpose |
| --- | --- | --- |
| Dashboard | `#/` | Summary cards and database capacity table with risk, environment, server, sorting, and contains filters. |
| Database Detail | `#/databases/:serverName/:databaseName` | Size trend chart and forecast details for one database. |
| Top Tables | `#/top-growing-tables` | Table growth ranking with environment, server, database, schema, sorting, and contains filters. |
| Alerts | `#/alerts` | Active alert queue with environment, server, severity, type, sorting, contains search, and More info evidence popup. |

The environment filter uses values populated by `pipelines/onboard-server.yml`: `Development`, `Test`, `QA`, `UAT`, `Production`, and `DR`.

## Important Files

| File | Purpose |
| --- | --- |
| `src/main.jsx` | Starts React, HashRouter, and timezone provider. |
| `src/App.jsx` | Defines route structure. |
| `src/components/Layout.jsx` | App shell, navigation, header, and timezone selector. |
| `src/components/TimezoneContext.jsx` | Stores selected UI time zone in local storage. |
| `src/components/formatters.js` | Number and date formatting. Treats repository timestamps as UTC. |
| `src/services/api.js` | API client wrapper using `VITE_API_BASE_URL`. |
| `src/pages/DashboardPage.jsx` | Main dashboard page. |
| `src/pages/DatabaseDetailPage.jsx` | Detail chart page. |
| `src/pages/TopGrowingTablesPage.jsx` | Top tables page. |
| `src/pages/AlertsPage.jsx` | Alert queue page and More info popup, including graphical query plan rendering for plan-aware alerts. |
| `src/styles.css` | Global layout, table, dashboard, alert, and responsive styles. |

## Alert More Info Popup

The alerts page reads `sourceScript` and `detailsJson` from `GET /api/alerts/active`.

The More info button opens a popup with:

- Alert time in the selected UI time zone.
- Server, database, severity, and alert type.
- Source script or procedure chain.
- Original alert message.
- Structured evidence from `detailsJson`.

For log and TempDB alerts, this can include projected hours to log cap, effective cap calculation inputs, recovery model, log reuse wait, last log backup time, long-running transaction details, or top TempDB-consuming sessions.

For long-running transaction and blocking alerts, the popup also searches `detailsJson` for:

- `queryPlanXml`
- `leadBlockerQueryPlanXml`
- `blockedQueryPlanXml`

When any of these fields are present, the popup renders a graphical SQL Server execution plan using `html-query-plan`. Multiple plans can be selected from the plan dropdown. The raw XML is intentionally hidden from the normal Evidence section so the popup stays readable.

Execution plans are best-effort. If SQL Server did not expose a cached plan during collection, the alert still shows SQL text and session evidence but no plan viewer.

Older active alerts may show a legacy evidence note until the next collector run creates fresh structured evidence.

## API URL Configuration

The web app uses:

```text
VITE_API_BASE_URL
```

Example:

```text
VITE_API_BASE_URL = http://localhost:5088/api
```

This is a build-time value. If it changes, rebuild and redeploy the web app.

## Time Zone Behavior

The header contains a time zone selector. The selected value is stored in browser local storage.

Repository timestamps are stored as UTC. SQL Server `DATETIME2` values may arrive without a `Z` suffix, so the formatter treats repository timestamp strings as UTC before displaying them in the selected time zone.

This affects:

- Database detail chart labels
- Alert time values

## Local Development

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

## Build

```powershell
cd .\web\dba-capacity-web
npm ci
npm run build
```

Build output:

```text
web/dba-capacity-web/dist
```

## IIS Hosting

Default IIS values:

```text
Site: DBA Capacity Dashboard
App pool: DBACapacityWeb
Path: C:\inetpub\dba-capacity-web
URL: http://localhost:8080
```

The app uses `HashRouter`, so IIS URL Rewrite is not required for client-side routes.

Example routes:

```text
http://localhost:8080/#/
http://localhost:8080/#/alerts
```

## Pipeline Deployment

Pipeline:

```text
pipelines/deploy-web.yml
```

The pipeline:

1. Installs Node.js.
2. Runs `npm ci`.
3. Runs `npm run build`.
4. Publishes the `dist` folder as a pipeline artifact.
5. Mirrors `dist` to the IIS physical path.
6. Starts the IIS website.

The agent service must run as a local administrator for IIS deployment.

## Customer Lift-And-Shift Notes

For a customer environment:

1. Decide the customer web URL and port.
2. Set `IIS_WEB_*` variables.
3. Set `VITE_API_BASE_URL` to the customer API URL.
4. Set API CORS variable `DBA_API_ALLOWED_ORIGINS` to include the customer web URL.
5. Deploy API first.
6. Deploy web second.
7. Validate dashboard, alerts, filters, sorting, and time zone selector.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Dashboard says database unavailable | API cannot reach SQL Server. | Check API `/health` and API logs. |
| Browser CORS error | API does not allow web origin. | Update `DBA_API_ALLOWED_ORIGINS` and redeploy API. |
| Web calls old API URL | `VITE_API_BASE_URL` was wrong at build time. | Correct variable and rerun Deploy Web. |
| Routes fail on refresh | BrowserRouter or IIS rewrite issue. | Current app uses HashRouter, redeploy current build. |
| Chart shows wrong time zone | Old web build deployed. | Deploy build with `parseRepositoryDateTime`. |
