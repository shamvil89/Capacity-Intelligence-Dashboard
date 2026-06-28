[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName,

    [int]$MinimumDurationMinutes = 15
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

if ($env:DBA_SOURCE_SERVER_TYPE -eq "AzureSQL") {
    Write-Host "Skipping long-running transaction metrics for Azure SQL Database $ServerName. The MVP collector uses instance-level DMVs for this signal."
    return
}

$query = @"
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME(dt.database_id) AS database_name,
    s.session_id,
    at.transaction_id,
    at.transaction_begin_time,
    CAST(DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) / 60.0 AS DECIMAL(18,2)) AS duration_minutes,
    s.login_name,
    s.host_name,
    s.program_name,
    at.name AS transaction_name,
    CASE at.transaction_type
        WHEN 1 THEN 'Read/write'
        WHEN 2 THEN 'Read-only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
        ELSE CONCAT('Unknown ', at.transaction_type)
    END AS transaction_type_desc,
    CASE at.transaction_state
        WHEN 0 THEN 'Not initialized'
        WHEN 1 THEN 'Initialized'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended'
        WHEN 4 THEN 'Commit initiated'
        WHEN 5 THEN 'Prepared'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling back'
        WHEN 8 THEN 'Rolled back'
        ELSE CONCAT('Unknown ', at.transaction_state)
    END AS transaction_state_desc,
    r.command,
    r.wait_type,
    r.blocking_session_id,
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
    ) AS sql_text,
    CONVERT(NVARCHAR(MAX), qp.query_plan) AS query_plan_xml
FROM sys.dm_tran_active_transactions AS at
INNER JOIN sys.dm_tran_session_transactions AS st
    ON st.transaction_id = at.transaction_id
INNER JOIN sys.dm_exec_sessions AS s
    ON s.session_id = st.session_id
LEFT JOIN sys.dm_tran_database_transactions AS dt
    ON dt.transaction_id = at.transaction_id
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS txt
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE s.is_user_process = 1
  AND at.transaction_begin_time <= DATEADD(MINUTE, -1 * CONVERT(INT, @MinimumDurationMinutes), GETDATE())
ORDER BY duration_minutes DESC;
"@

Write-Host "Collecting long-running transaction metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $query -SqlParameter @{
    MinimumDurationMinutes = $MinimumDurationMinutes
})

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertLongRunningTransactionHistory" -SqlParameter @{
        server_name              = [string]$row.server_name
        database_name            = ConvertTo-NullableValue $row.database_name
        session_id               = ConvertTo-NullableValue $row.session_id
        transaction_id           = ConvertTo-NullableValue $row.transaction_id
        transaction_begin_time   = ConvertTo-NullableValue $row.transaction_begin_time
        duration_minutes         = ConvertTo-NullableValue $row.duration_minutes
        login_name               = ConvertTo-NullableValue $row.login_name
        host_name                = ConvertTo-NullableValue $row.host_name
        program_name             = ConvertTo-NullableValue $row.program_name
        transaction_name         = ConvertTo-NullableValue $row.transaction_name
        transaction_type_desc    = ConvertTo-NullableValue $row.transaction_type_desc
        transaction_state_desc   = ConvertTo-NullableValue $row.transaction_state_desc
        command                  = ConvertTo-NullableValue $row.command
        wait_type                = ConvertTo-NullableValue $row.wait_type
        blocking_session_id      = ConvertTo-NullableValue $row.blocking_session_id
        sql_text                 = ConvertTo-NullableValue $row.sql_text
        query_plan_xml           = ConvertTo-NullableValue $row.query_plan_xml
    }
}

Write-Host "Inserted $($rows.Count) long-running transaction rows for $ServerName."
