[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$databaseQuery = @"
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4
  AND source_database_id IS NULL
ORDER BY name;
"@

$tableQuery = @"
WITH row_counts AS
(
    SELECT
        t.object_id,
        SUM(CASE WHEN i.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS row_count
    FROM sys.tables AS t
    INNER JOIN sys.indexes AS i
        ON i.object_id = t.object_id
    INNER JOIN sys.partitions AS p
        ON p.object_id = i.object_id
       AND p.index_id = i.index_id
    WHERE t.is_ms_shipped = 0
    GROUP BY t.object_id
),
space_usage AS
(
    SELECT
        t.object_id,
        SUM(a.total_pages) * 8.0 / 1024.0 AS total_mb,
        SUM(a.used_pages) * 8.0 / 1024.0 AS used_mb,
        SUM(a.data_pages) * 8.0 / 1024.0 AS data_mb
    FROM sys.tables AS t
    INNER JOIN sys.indexes AS i
        ON i.object_id = t.object_id
    INNER JOIN sys.partitions AS p
        ON p.object_id = i.object_id
       AND p.index_id = i.index_id
    LEFT JOIN sys.allocation_units AS a
        ON (a.type IN (1, 3) AND a.container_id = p.hobt_id)
        OR (a.type = 2 AND a.container_id = p.partition_id)
    WHERE t.is_ms_shipped = 0
    GROUP BY t.object_id
)
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    s.name AS schema_name,
    t.name AS table_name,
    rc.row_count,
    CAST(su.total_mb AS DECIMAL(18,2)) AS total_mb,
    CAST(su.used_mb AS DECIMAL(18,2)) AS used_mb,
    CAST(su.data_mb AS DECIMAL(18,2)) AS data_mb,
    CAST(su.used_mb - su.data_mb AS DECIMAL(18,2)) AS index_mb
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
LEFT JOIN row_counts AS rc
    ON rc.object_id = t.object_id
LEFT JOIN space_usage AS su
    ON su.object_id = t.object_id
WHERE t.is_ms_shipped = 0
ORDER BY su.total_mb DESC, s.name, t.name;
"@

Write-Host "Collecting table size metrics from $ServerName..."
$databases = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $databaseQuery)
$inserted = 0

foreach ($database in $databases) {
    $databaseName = [string]$database.name

    try {
        $rows = @(Invoke-SourceQuery -ServerName $ServerName -Database $databaseName -Query $tableQuery)

        foreach ($row in $rows) {
            Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertTableSizeHistory" -SqlParameter @{
                server_name   = [string]$row.server_name
                database_name = [string]$row.database_name
                schema_name   = [string]$row.schema_name
                table_name    = [string]$row.table_name
                row_count     = ConvertTo-NullableValue $row.row_count
                total_mb      = ConvertTo-NullableValue $row.total_mb
                used_mb       = ConvertTo-NullableValue $row.used_mb
                data_mb       = ConvertTo-NullableValue $row.data_mb
                index_mb      = ConvertTo-NullableValue $row.index_mb
            }
        }

        $inserted += $rows.Count
    }
    catch {
        Write-Warning "Table size collection failed for $ServerName/$databaseName. $($_.Exception.Message)"
        Write-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "TableSize" -Message $_.Exception.Message
    }
}

Write-Host "Inserted $inserted table size rows for $ServerName."
