[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$query = @"
SELECT
    @@SERVERNAME AS server_name,
    CAST(df.tempdb_size_mb AS DECIMAL(18,2)) AS tempdb_size_mb,
    CAST(fs.user_objects_mb AS DECIMAL(18,2)) AS user_objects_mb,
    CAST(fs.internal_objects_mb AS DECIMAL(18,2)) AS internal_objects_mb,
    CAST(fs.version_store_mb AS DECIMAL(18,2)) AS version_store_mb,
    CAST(fs.free_space_mb AS DECIMAL(18,2)) AS free_space_mb
FROM
(
    SELECT SUM(size) * 8.0 / 1024.0 AS tempdb_size_mb
    FROM tempdb.sys.database_files
) AS df
CROSS JOIN
(
    SELECT
        SUM(user_object_reserved_page_count) * 8.0 / 1024.0 AS user_objects_mb,
        SUM(internal_object_reserved_page_count) * 8.0 / 1024.0 AS internal_objects_mb,
        SUM(version_store_reserved_page_count) * 8.0 / 1024.0 AS version_store_mb,
        SUM(unallocated_extent_page_count) * 8.0 / 1024.0 AS free_space_mb
    FROM tempdb.sys.dm_db_file_space_usage
) AS fs;
"@

Write-Host "Collecting TempDB usage metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database tempdb -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertTempDBUsageHistory" -SqlParameter @{
        server_name         = [string]$row.server_name
        tempdb_size_mb      = ConvertTo-NullableValue $row.tempdb_size_mb
        user_objects_mb     = ConvertTo-NullableValue $row.user_objects_mb
        internal_objects_mb = ConvertTo-NullableValue $row.internal_objects_mb
        version_store_mb    = ConvertTo-NullableValue $row.version_store_mb
        free_space_mb       = ConvertTo-NullableValue $row.free_space_mb
    }
}

Write-Host "Inserted $($rows.Count) TempDB usage rows for $ServerName."
