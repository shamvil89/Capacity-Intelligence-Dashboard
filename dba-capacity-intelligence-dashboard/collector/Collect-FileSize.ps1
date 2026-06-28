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
    df.name AS logical_file_name,
    df.physical_name AS physical_file_name,
    df.type_desc AS file_type,
    CAST(df.size * 8.0 / 1024.0 AS DECIMAL(18,2)) AS file_size_mb,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') * 8.0 / 1024.0 AS DECIMAL(18,2)) AS used_space_mb,
    CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS free_space_mb,
    CASE
        WHEN df.is_percent_growth = 1 THEN CONCAT(df.growth, '%')
        ELSE CONCAT(CAST(df.growth * 8.0 / 1024.0 AS DECIMAL(18,2)), ' MB')
    END AS growth_setting,
    CASE
        WHEN df.max_size = -1 THEN NULL
        WHEN df.max_size = 268435456 THEN NULL
        ELSE CAST(df.max_size * 8.0 / 1024.0 AS DECIMAL(18,2))
    END AS max_size_mb,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    vs.volume_mount_point,
    CAST(vs.total_bytes / 1073741824.0 AS DECIMAL(18,2)) AS volume_total_gb,
    CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(18,2)) AS volume_available_gb
FROM sys.database_files AS df
INNER JOIN sys.databases AS d
    ON d.name = DB_NAME()
CROSS APPLY sys.dm_os_volume_stats(DB_ID(), df.file_id) AS vs
ORDER BY df.type_desc, df.name;
"@

$azureSqlFileQuery = @"
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME() AS database_name,
    df.name AS logical_file_name,
    df.physical_name AS physical_file_name,
    df.type_desc AS file_type,
    CAST(df.size * 8.0 / 1024.0 AS DECIMAL(18,2)) AS file_size_mb,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') * 8.0 / 1024.0 AS DECIMAL(18,2)) AS used_space_mb,
    CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS free_space_mb,
    CASE
        WHEN df.is_percent_growth = 1 THEN CONCAT(df.growth, '%')
        ELSE CONCAT(CAST(df.growth * 8.0 / 1024.0 AS DECIMAL(18,2)), ' MB')
    END AS growth_setting,
    CASE
        WHEN df.max_size = -1 THEN NULL
        WHEN df.max_size = 268435456 THEN NULL
        ELSE CAST(df.max_size * 8.0 / 1024.0 AS DECIMAL(18,2))
    END AS max_size_mb,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    CAST(NULL AS NVARCHAR(512)) AS volume_mount_point,
    CAST(NULL AS DECIMAL(18,2)) AS volume_total_gb,
    CAST(NULL AS DECIMAL(18,2)) AS volume_available_gb
FROM sys.database_files AS df
INNER JOIN sys.databases AS d
    ON d.name = DB_NAME()
ORDER BY df.type_desc, df.name;
"@

Write-Host "Collecting file size metrics from $ServerName..."
$databases = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $databaseQuery)
$inserted = 0

Resolve-CollectionFailureAlertsForMetric -ServerName $ServerName -MetricName "FileSize"

foreach ($database in $databases) {
    $databaseName = [string]$database.name

    try {
        $query = if ($env:DBA_SOURCE_SERVER_TYPE -eq "AzureSQL") { $azureSqlFileQuery } else { $fileQuery }
        $rows = @(Invoke-SourceQuery -ServerName $ServerName -Database $databaseName -Query $query)

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
                recovery_model_desc = ConvertTo-NullableValue $row.recovery_model_desc
                log_reuse_wait_desc = ConvertTo-NullableValue $row.log_reuse_wait_desc
                volume_mount_point  = ConvertTo-NullableValue $row.volume_mount_point
                volume_total_gb     = ConvertTo-NullableValue $row.volume_total_gb
                volume_available_gb = ConvertTo-NullableValue $row.volume_available_gb
            }
        }

        $inserted += $rows.Count
        Resolve-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "FileSize"
    }
    catch {
        Write-Warning "File size collection failed for $ServerName/$databaseName. $($_.Exception.Message)"
        Write-CollectionFailureAlert -ServerName $ServerName -DatabaseName $databaseName -MetricName "FileSize" -Message $_.Exception.Message
    }
}

Write-Host "Inserted $inserted file size rows for $ServerName."
