[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$query = @"
WITH BlockedRequests AS
(
    SELECT
        r.session_id AS blocked_session_id,
        r.blocking_session_id AS immediate_blocker_session_id,
        r.database_id,
        r.start_time,
        r.status,
        r.command,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.sql_handle,
        r.plan_handle,
        r.statement_start_offset,
        r.statement_end_offset
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id > 0
),
BlockChain AS
(
    SELECT
        br.blocked_session_id,
        br.immediate_blocker_session_id AS current_blocker_session_id,
        1 AS depth
    FROM BlockedRequests AS br

    UNION ALL

    SELECT
        bc.blocked_session_id,
        r.blocking_session_id AS current_blocker_session_id,
        bc.depth + 1 AS depth
    FROM BlockChain AS bc
    INNER JOIN sys.dm_exec_requests AS r
        ON r.session_id = bc.current_blocker_session_id
    WHERE r.blocking_session_id > 0
      AND r.blocking_session_id <> r.session_id
      AND bc.depth < 20
),
LeadBlocker AS
(
    SELECT
        blocked_session_id,
        current_blocker_session_id AS lead_blocker_session_id,
        ROW_NUMBER() OVER
        (
            PARTITION BY blocked_session_id
            ORDER BY depth DESC
        ) AS rn
    FROM BlockChain
),
SessionTransactions AS
(
    SELECT
        st.session_id,
        MIN(at.transaction_begin_time) AS transaction_begin_time
    FROM sys.dm_tran_session_transactions AS st
    INNER JOIN sys.dm_tran_active_transactions AS at
        ON at.transaction_id = st.transaction_id
    GROUP BY st.session_id
),
WaitingLocks AS
(
    SELECT
        l.request_session_id,
        l.resource_database_id,
        l.resource_type,
        l.request_mode,
        CASE
            WHEN l.resource_type = 'OBJECT'
                THEN l.resource_associated_entity_id
            ELSE p.object_id
        END AS object_id,
        ROW_NUMBER() OVER
        (
            PARTITION BY l.request_session_id
            ORDER BY
                CASE WHEN l.request_status = 'WAIT' THEN 0 ELSE 1 END,
                l.request_mode
        ) AS rn
    FROM sys.dm_tran_locks AS l
    LEFT JOIN sys.partitions AS p
        ON p.hobt_id = l.resource_associated_entity_id
    WHERE l.request_status = 'WAIT'
)
SELECT
    @@SERVERNAME AS server_name,
    DB_NAME(br.database_id) AS database_name,
    lb.lead_blocker_session_id,
    bs.login_name AS lead_blocker_login_name,
    bs.host_name AS lead_blocker_host_name,
    bs.program_name AS lead_blocker_program_name,
    bs.status AS lead_blocker_status,
    brq.command AS lead_blocker_command,
    COALESCE(brq.start_time, bs.last_request_start_time, bt.transaction_begin_time) AS lead_blocker_running_since,
    CAST
    (
        DATEDIFF
        (
            SECOND,
            COALESCE(brq.start_time, bs.last_request_start_time, bt.transaction_begin_time),
            GETDATE()
        ) / 60.0 AS DECIMAL(18,2)
    ) AS lead_blocker_duration_minutes,
    bt.transaction_begin_time AS lead_blocker_transaction_begin_time,
    brq.wait_type AS lead_blocker_wait_type,
    LEFT
    (
        CASE
            WHEN blocker_text.text IS NULL THEN NULL
            WHEN brq.statement_start_offset IS NULL THEN blocker_text.text
            ELSE SUBSTRING
            (
                blocker_text.text,
                (brq.statement_start_offset / 2) + 1,
                (
                    (
                        CASE brq.statement_end_offset
                            WHEN -1 THEN DATALENGTH(blocker_text.text)
                            ELSE brq.statement_end_offset
                        END - brq.statement_start_offset
                    ) / 2
                ) + 1
            )
        END,
        4000
    ) AS lead_blocker_sql_text,
    CONVERT(NVARCHAR(MAX), blocker_plan.query_plan) AS lead_blocker_query_plan_xml,
    br.blocked_session_id,
    blocked_session.login_name AS blocked_login_name,
    blocked_session.host_name AS blocked_host_name,
    blocked_session.program_name AS blocked_program_name,
    br.status AS blocked_status,
    br.command AS blocked_command,
    br.start_time AS blocked_start_time,
    br.wait_type AS blocked_wait_type,
    br.wait_time AS blocked_wait_duration_ms,
    br.wait_resource AS blocked_wait_resource,
    CASE
        WHEN wl.object_id IS NOT NULL
            THEN CONCAT(OBJECT_SCHEMA_NAME(wl.object_id, wl.resource_database_id), N'.', OBJECT_NAME(wl.object_id, wl.resource_database_id))
        ELSE NULL
    END AS blocked_object_name,
    wl.request_mode AS blocked_lock_mode,
    LEFT
    (
        CASE
            WHEN blocked_text.text IS NULL THEN NULL
            ELSE SUBSTRING
            (
                blocked_text.text,
                (br.statement_start_offset / 2) + 1,
                (
                    (
                        CASE br.statement_end_offset
                            WHEN -1 THEN DATALENGTH(blocked_text.text)
                            ELSE br.statement_end_offset
                        END - br.statement_start_offset
                    ) / 2
                ) + 1
            )
        END,
        4000
    ) AS blocked_sql_text,
    CONVERT(NVARCHAR(MAX), blocked_plan.query_plan) AS blocked_query_plan_xml,
    blocker_locks.blocker_locks_json
FROM BlockedRequests AS br
INNER JOIN LeadBlocker AS lb
    ON lb.blocked_session_id = br.blocked_session_id
   AND lb.rn = 1
LEFT JOIN sys.dm_exec_sessions AS blocked_session
    ON blocked_session.session_id = br.blocked_session_id
LEFT JOIN sys.dm_exec_sessions AS bs
    ON bs.session_id = lb.lead_blocker_session_id
LEFT JOIN sys.dm_exec_requests AS brq
    ON brq.session_id = lb.lead_blocker_session_id
LEFT JOIN sys.dm_exec_connections AS blocker_connection
    ON blocker_connection.session_id = lb.lead_blocker_session_id
LEFT JOIN SessionTransactions AS bt
    ON bt.session_id = lb.lead_blocker_session_id
LEFT JOIN WaitingLocks AS wl
    ON wl.request_session_id = br.blocked_session_id
   AND wl.rn = 1
OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) AS blocked_text
OUTER APPLY sys.dm_exec_sql_text(COALESCE(brq.sql_handle, blocker_connection.most_recent_sql_handle)) AS blocker_text
OUTER APPLY sys.dm_exec_query_plan(brq.plan_handle) AS blocker_plan
OUTER APPLY sys.dm_exec_query_plan(br.plan_handle) AS blocked_plan
OUTER APPLY
(
    SELECT
        COALESCE
        (
            (
                SELECT TOP (30)
                    DB_NAME(l.resource_database_id) AS databaseName,
                    l.resource_type AS resourceType,
                    l.request_mode AS lockMode,
                    l.request_status AS lockStatus,
                    CASE
                        WHEN l.resource_type = 'OBJECT'
                            THEN CONCAT(OBJECT_SCHEMA_NAME(CONVERT(INT, l.resource_associated_entity_id), l.resource_database_id), N'.', OBJECT_NAME(CONVERT(INT, l.resource_associated_entity_id), l.resource_database_id))
                        WHEN p.object_id IS NOT NULL
                            THEN CONCAT(OBJECT_SCHEMA_NAME(p.object_id, l.resource_database_id), N'.', OBJECT_NAME(p.object_id, l.resource_database_id))
                        ELSE NULL
                    END AS objectName
                FROM sys.dm_tran_locks AS l
                LEFT JOIN sys.partitions AS p
                    ON p.hobt_id = l.resource_associated_entity_id
                WHERE l.request_session_id = lb.lead_blocker_session_id
                  AND l.request_status = 'GRANT'
                  AND l.resource_type IN ('OBJECT', 'KEY', 'PAGE', 'RID', 'HOBT')
                ORDER BY l.resource_database_id, objectName, l.request_mode
                FOR JSON PATH
            ),
            N'[]'
        ) AS blocker_locks_json
) AS blocker_locks
OPTION (MAXRECURSION 20);
"@

Write-Host "Collecting blocking session metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertBlockingSessionHistory" -SqlParameter @{
        server_name                           = [string]$row.server_name
        database_name                         = ConvertTo-NullableValue $row.database_name
        lead_blocker_session_id               = $row.lead_blocker_session_id
        lead_blocker_login_name               = ConvertTo-NullableValue $row.lead_blocker_login_name
        lead_blocker_host_name                = ConvertTo-NullableValue $row.lead_blocker_host_name
        lead_blocker_program_name             = ConvertTo-NullableValue $row.lead_blocker_program_name
        lead_blocker_status                   = ConvertTo-NullableValue $row.lead_blocker_status
        lead_blocker_command                  = ConvertTo-NullableValue $row.lead_blocker_command
        lead_blocker_running_since            = ConvertTo-NullableValue $row.lead_blocker_running_since
        lead_blocker_duration_minutes         = ConvertTo-NullableValue $row.lead_blocker_duration_minutes
        lead_blocker_transaction_begin_time   = ConvertTo-NullableValue $row.lead_blocker_transaction_begin_time
        lead_blocker_wait_type                = ConvertTo-NullableValue $row.lead_blocker_wait_type
        lead_blocker_sql_text                 = ConvertTo-NullableValue $row.lead_blocker_sql_text
        lead_blocker_query_plan_xml           = ConvertTo-NullableValue $row.lead_blocker_query_plan_xml
        blocked_session_id                    = $row.blocked_session_id
        blocked_login_name                    = ConvertTo-NullableValue $row.blocked_login_name
        blocked_host_name                     = ConvertTo-NullableValue $row.blocked_host_name
        blocked_program_name                  = ConvertTo-NullableValue $row.blocked_program_name
        blocked_status                        = ConvertTo-NullableValue $row.blocked_status
        blocked_command                       = ConvertTo-NullableValue $row.blocked_command
        blocked_start_time                    = ConvertTo-NullableValue $row.blocked_start_time
        blocked_wait_type                     = ConvertTo-NullableValue $row.blocked_wait_type
        blocked_wait_duration_ms              = ConvertTo-NullableValue $row.blocked_wait_duration_ms
        blocked_wait_resource                 = ConvertTo-NullableValue $row.blocked_wait_resource
        blocked_object_name                   = ConvertTo-NullableValue $row.blocked_object_name
        blocked_lock_mode                     = ConvertTo-NullableValue $row.blocked_lock_mode
        blocked_sql_text                      = ConvertTo-NullableValue $row.blocked_sql_text
        blocked_query_plan_xml                = ConvertTo-NullableValue $row.blocked_query_plan_xml
        blocker_locks_json                    = ConvertTo-NullableValue $row.blocker_locks_json
    }
}

Write-Host "Inserted $($rows.Count) blocking session rows for $ServerName."
