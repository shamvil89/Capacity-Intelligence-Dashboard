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
    DB_NAME(database_id) AS database_name,
    CAST(SUM(size) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS total_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'ROWS' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS data_size_mb,
    CAST(SUM(CASE WHEN type_desc = 'LOG' THEN size ELSE 0 END) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS log_size_mb
FROM sys.master_files
GROUP BY database_id
ORDER BY database_name;
"@

Write-Host "Collecting database size metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertDatabaseSizeHistory" -SqlParameter @{
        server_name   = [string]$row.server_name
        database_name = [string]$row.database_name
        total_size_mb = $row.total_size_mb
        data_size_mb  = ConvertTo-NullableValue $row.data_size_mb
        log_size_mb   = ConvertTo-NullableValue $row.log_size_mb
    }
}

Write-Host "Inserted $($rows.Count) database size rows for $ServerName."
