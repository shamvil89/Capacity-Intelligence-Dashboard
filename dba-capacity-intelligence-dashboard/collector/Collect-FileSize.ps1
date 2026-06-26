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
  AND source_database_id IS NULL
ORDER BY name;
"@

$fileQuery = @"
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    name AS logical_file_name,
    physical_name AS physical_file_name,
    type_desc AS file_type,
    CAST(size * 8.0 / 1024.0 AS DECIMAL(18,2)) AS file_size_mb,
    CAST(FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024.0 AS DECIMAL(18,2)) AS used_space_mb,
    CAST((size - FILEPROPERTY(name, 'SpaceUsed')) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS free_space_mb,
    CASE
        WHEN is_percent_growth = 1 THEN CONCAT(growth, '%')
        ELSE CONCAT(CAST(growth * 8.0 / 1024.0 AS DECIMAL(18,2)), ' MB')
    END AS growth_setting,
    CASE
        WHEN max_size = -1 THEN NULL
        WHEN max_size = 268435456 THEN NULL
        ELSE CAST(max_size * 8.0 / 1024.0 AS DECIMAL(18,2))
    END AS max_size_mb
FROM sys.database_files
ORDER BY type_desc, name;
"@

Write-Host "Collecting file size metrics from $ServerName..."
$databases = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $databaseQuery)
$inserted = 0

foreach ($database in $databases) {
    $databaseName = [string]$database.name

    try {
        $rows = @(Invoke-SourceQuery -ServerName $ServerName -Database $databaseName -Query $fileQuery)

        foreach ($row in $rows) {
            Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertFileSizeHistory" -SqlParameter @{
                server_name        = [string]$row.server_name
                database_name      = [string]$row.database_name
                logical_file_name  = [string]$row.logical_file_name
                physical_file_name = ConvertTo-NullableValue $row.physical_file_name
                file_type          = [string]$row.file_type
                file_size_mb       = $row.file_size_mb
                used_space_mb      = ConvertTo-NullableValue $row.used_space_mb
                free_space_mb      = ConvertTo-NullableValue $row.free_space_mb
                growth_setting     = ConvertTo-NullableValue $row.growth_setting
                max_size_mb        = ConvertTo-NullableValue $row.max_size_mb
            }
        }

        $inserted += $rows.Count
    }
    catch {
        Write-Warning "File size collection failed for $ServerName/$databaseName. $($_.Exception.Message)"
        Write-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "FileSize" -Message $_.Exception.Message
    }
}

Write-Host "Inserted $inserted file size rows for $ServerName."
