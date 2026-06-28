[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$databaseSizeQuery = @"
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME(database_id) AS database_name,
    CAST(SUM(size) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS total_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'ROWS' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS data_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'LOG' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS log_size_mb
FROM sys.master_files
GROUP BY database_id
ORDER BY database_name;
"@

$azureSqlDatabaseQuery = @"
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND name <> N'master'
  AND source_database_id IS NULL
ORDER BY name;
"@

$azureSqlDatabaseSizeQuery = @"
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    CAST(SUM(size) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS total_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'ROWS' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS data_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'LOG' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS log_size_mb
FROM sys.database_files;
"@

Write-Host "Collecting database size metrics from $ServerName..."

if ($env:DBA_SOURCE_SERVER_TYPE -eq "AzureSQL") {
    $databases = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $azureSqlDatabaseQuery)
    $inserted = 0

    Resolve-CollectionFailureAlertsForMetric -ServerName $ServerName -MetricName "DatabaseSize"

    foreach ($database in $databases) {
        $databaseName = [string]$database.name

        try {
            $rows = @(Invoke-SourceQuery -ServerName $ServerName -Database $databaseName -Query $azureSqlDatabaseSizeQuery)

            foreach ($row in $rows) {
                Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertDatabaseSizeHistory" -SqlParameter @{
                    server_name   = [string]$row.server_name
                    database_name = [string]$row.database_name
                    total_size_mb = $row.total_size_mb
                    data_size_mb  = ConvertTo-NullableValue $row.data_size_mb
                    log_size_mb   = ConvertTo-NullableValue $row.log_size_mb
                }
            }

            $inserted += $rows.Count
            Resolve-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "DatabaseSize"
        }
        catch {
            Write-Warning "Database size collection failed for $ServerName/$databaseName. $($_.Exception.Message)"
            Write-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "DatabaseSize" -Message $_.Exception.Message
        }
    }

    Write-Host "Inserted $inserted database size rows for $ServerName."
    return
}

$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $databaseSizeQuery)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertDatabaseSizeHistory" -SqlParameter @{
        server_name   = [string]$row.server_name
        database_name = [string]$row.database_name
        total_size_mb = $row.total_size_mb
        data_size_mb  = ConvertTo-NullableValue $row.data_size_mb
        log_size_mb   = ConvertTo-NullableValue $row.log_size_mb
    }
}

Resolve-CollectionFailureAlert -ServerName $ServerName -DatabaseName $null -MetricName "DatabaseSize"
Write-Host "Inserted $($rows.Count) database size rows for $ServerName."
