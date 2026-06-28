[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$hadrQuery = "SELECT CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) AS is_hadr_enabled;"
$hadrState = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $hadrQuery)

if ($hadrState.Count -eq 0 -or [int]$hadrState[0].is_hadr_enabled -ne 1) {
    Write-Host "Skipping Always On health for $ServerName because Always On availability groups are not enabled."
    return
}

$query = @"
SELECT
    @@SERVERNAME AS server_name,
    ag.name AS availability_group_name,
    ar.replica_server_name,
    DB_NAME(drs.database_id) AS database_name,
    ars.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc AS replica_synchronization_health_desc,
    drs.synchronization_state_desc AS database_synchronization_state_desc,
    drs.synchronization_health_desc AS database_synchronization_health_desc,
    drs.database_state_desc,
    drs.is_suspended,
    drs.suspend_reason_desc,
    drs.log_send_queue_size AS log_send_queue_size_kb,
    drs.redo_queue_size AS redo_queue_size_kb,
    drs.log_send_rate AS log_send_rate_kb_per_sec,
    drs.redo_rate AS redo_rate_kb_per_sec,
    drs.last_sent_time,
    drs.last_received_time,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.last_commit_time,
    ars.last_connect_error_number,
    ars.last_connect_error_description,
    ars.last_connect_error_timestamp
FROM sys.availability_groups AS ag
INNER JOIN sys.availability_replicas AS ar
    ON ar.group_id = ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
    ON ars.group_id = ar.group_id
   AND ars.replica_id = ar.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states AS drs
    ON drs.group_id = ar.group_id
   AND drs.replica_id = ar.replica_id
ORDER BY ag.name, ar.replica_server_name, database_name;
"@

Write-Host "Collecting Always On health from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertAlwaysOnHealthHistory" -SqlParameter @{
        server_name                                 = [string]$row.server_name
        availability_group_name                     = ConvertTo-NullableValue $row.availability_group_name
        replica_server_name                         = ConvertTo-NullableValue $row.replica_server_name
        database_name                               = ConvertTo-NullableValue $row.database_name
        role_desc                                   = ConvertTo-NullableValue $row.role_desc
        operational_state_desc                      = ConvertTo-NullableValue $row.operational_state_desc
        connected_state_desc                        = ConvertTo-NullableValue $row.connected_state_desc
        replica_synchronization_health_desc         = ConvertTo-NullableValue $row.replica_synchronization_health_desc
        database_synchronization_state_desc         = ConvertTo-NullableValue $row.database_synchronization_state_desc
        database_synchronization_health_desc        = ConvertTo-NullableValue $row.database_synchronization_health_desc
        database_state_desc                         = ConvertTo-NullableValue $row.database_state_desc
        is_suspended                                = ConvertTo-NullableValue $row.is_suspended
        suspend_reason_desc                         = ConvertTo-NullableValue $row.suspend_reason_desc
        log_send_queue_size_kb                      = ConvertTo-NullableValue $row.log_send_queue_size_kb
        redo_queue_size_kb                          = ConvertTo-NullableValue $row.redo_queue_size_kb
        log_send_rate_kb_per_sec                    = ConvertTo-NullableValue $row.log_send_rate_kb_per_sec
        redo_rate_kb_per_sec                        = ConvertTo-NullableValue $row.redo_rate_kb_per_sec
        last_sent_time                              = ConvertTo-NullableValue $row.last_sent_time
        last_received_time                          = ConvertTo-NullableValue $row.last_received_time
        last_hardened_time                          = ConvertTo-NullableValue $row.last_hardened_time
        last_redone_time                            = ConvertTo-NullableValue $row.last_redone_time
        last_commit_time                            = ConvertTo-NullableValue $row.last_commit_time
        last_connect_error_number                   = ConvertTo-NullableValue $row.last_connect_error_number
        last_connect_error_description              = ConvertTo-NullableValue $row.last_connect_error_description
        last_connect_error_timestamp                = ConvertTo-NullableValue $row.last_connect_error_timestamp
    }
}

Write-Host "Inserted $($rows.Count) Always On health rows for $ServerName."
