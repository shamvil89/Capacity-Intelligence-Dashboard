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

$topConsumersQuery = @"
WITH SessionUsage AS
(
    SELECT
        ssu.session_id,
        CAST((ssu.user_objects_alloc_page_count - ssu.user_objects_dealloc_page_count) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS user_objects_mb,
        CAST((ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count) * 8.0 / 1024.0 AS DECIMAL(18,2)) AS internal_objects_mb
    FROM sys.dm_db_session_space_usage AS ssu
)
SELECT TOP (10)
    @@SERVERNAME AS server_name,
    su.session_id,
    r.request_id,
    DB_NAME(COALESCE(r.database_id, s.database_id)) AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    r.command,
    r.wait_type,
    r.blocking_session_id,
    su.user_objects_mb,
    su.internal_objects_mb,
    CAST(ISNULL(su.user_objects_mb, 0) + ISNULL(su.internal_objects_mb, 0) AS DECIMAL(18,2)) AS total_allocated_mb,
    LEFT(
        CASE
            WHEN r.sql_handle IS NULL THEN NULL
            ELSE SUBSTRING
            (
                txt.text,
                (r.statement_start_offset / 2) + 1,
                (
                    (
                        CASE r.statement_end_offset
                            WHEN -1 THEN DATALENGTH(txt.text)
                            ELSE r.statement_end_offset
                        END - r.statement_start_offset
                    ) / 2
                ) + 1
            )
        END,
        4000
    ) AS sql_text
FROM SessionUsage AS su
INNER JOIN sys.dm_exec_sessions AS s
    ON s.session_id = su.session_id
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = su.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS txt
WHERE s.is_user_process = 1
  AND ISNULL(su.user_objects_mb, 0) + ISNULL(su.internal_objects_mb, 0) > 0
ORDER BY total_allocated_mb DESC;
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

$consumerRows = @(Invoke-SourceQuery -ServerName $ServerName -Database tempdb -Query $topConsumersQuery)

foreach ($row in $consumerRows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertTempDBSessionUsageHistory" -SqlParameter @{
        server_name         = [string]$row.server_name
        session_id          = $row.session_id
        request_id          = ConvertTo-NullableValue $row.request_id
        database_name       = ConvertTo-NullableValue $row.database_name
        login_name          = ConvertTo-NullableValue $row.login_name
        host_name           = ConvertTo-NullableValue $row.host_name
        program_name        = ConvertTo-NullableValue $row.program_name
        status              = ConvertTo-NullableValue $row.status
        command             = ConvertTo-NullableValue $row.command
        wait_type           = ConvertTo-NullableValue $row.wait_type
        blocking_session_id = ConvertTo-NullableValue $row.blocking_session_id
        user_objects_mb     = ConvertTo-NullableValue $row.user_objects_mb
        internal_objects_mb = ConvertTo-NullableValue $row.internal_objects_mb
        total_allocated_mb  = ConvertTo-NullableValue $row.total_allocated_mb
        sql_text            = ConvertTo-NullableValue $row.sql_text
    }
}

Write-Host "Inserted $($rows.Count) TempDB usage rows for $ServerName."
Write-Host "Inserted $($consumerRows.Count) TempDB top consumer rows for $ServerName."
