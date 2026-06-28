[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$databaseFlagQuery = @"
SELECT
    @@SERVERNAME AS server_name,
    name AS database_name,
    CAST(is_published AS BIT) AS is_published,
    CAST(is_subscribed AS BIT) AS is_subscribed,
    CAST(is_merge_published AS BIT) AS is_merge_published,
    CAST(is_distributor AS BIT) AS is_distributor
FROM sys.databases
WHERE is_published = 1
   OR is_subscribed = 1
   OR is_merge_published = 1
   OR is_distributor = 1
ORDER BY name;
"@

$distributionExistsQuery = "SELECT DB_ID(N'distribution') AS distribution_database_id;"

$agentQuery = @"
CREATE TABLE #ReplicationAgentStatus
(
    server_name SYSNAME NOT NULL,
    database_name SYSNAME NULL,
    publication NVARCHAR(256) NULL,
    agent_type NVARCHAR(80) NULL,
    agent_name NVARCHAR(256) NULL,
    subscriber_name NVARCHAR(256) NULL,
    subscriber_database_name SYSNAME NULL,
    run_status INT NULL,
    run_status_desc NVARCHAR(60) NULL,
    last_event_time DATETIME NULL,
    latency_seconds BIGINT NULL,
    delivered_commands BIGINT NULL,
    delivery_rate DECIMAL(18,2) NULL,
    error_id INT NULL,
    error_code INT NULL,
    error_text NVARCHAR(MAX) NULL,
    comments NVARCHAR(MAX) NULL
);

IF OBJECT_ID(N'dbo.MSlogreader_agents', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MSlogreader_history', N'U') IS NOT NULL
BEGIN
    ;WITH LatestHistory AS
    (
        SELECT
            h.*,
            ROW_NUMBER() OVER (PARTITION BY h.agent_id ORDER BY h.time DESC) AS rn
        FROM dbo.MSlogreader_history AS h
    )
    INSERT INTO #ReplicationAgentStatus
    SELECT
        @@SERVERNAME,
        a.publisher_db,
        a.publication,
        N'LogReader',
        a.name,
        NULL,
        NULL,
        h.runstatus,
        CASE h.runstatus WHEN 1 THEN N'Started' WHEN 2 THEN N'Succeeded' WHEN 3 THEN N'InProgress' WHEN 4 THEN N'Idle' WHEN 5 THEN N'Retry' WHEN 6 THEN N'Failed' ELSE CONVERT(NVARCHAR(60), h.runstatus) END,
        h.time,
        h.duration,
        NULL,
        NULL,
        h.error_id,
        e.error_code,
        e.error_text,
        h.comments
    FROM dbo.MSlogreader_agents AS a
    LEFT JOIN LatestHistory AS h
        ON h.agent_id = a.id
       AND h.rn = 1
    LEFT JOIN dbo.MSrepl_errors AS e
        ON e.id = h.error_id;
END;

IF OBJECT_ID(N'dbo.MSdistribution_agents', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MSdistribution_history', N'U') IS NOT NULL
BEGIN
    ;WITH LatestHistory AS
    (
        SELECT
            h.*,
            ROW_NUMBER() OVER (PARTITION BY h.agent_id ORDER BY h.time DESC) AS rn
        FROM dbo.MSdistribution_history AS h
    )
    INSERT INTO #ReplicationAgentStatus
    SELECT
        @@SERVERNAME,
        a.publisher_db,
        a.publication,
        N'Distribution',
        a.name,
        COALESCE(si.name, CONVERT(NVARCHAR(256), a.subscriber_id)),
        a.subscriber_db,
        h.runstatus,
        CASE h.runstatus WHEN 1 THEN N'Started' WHEN 2 THEN N'Succeeded' WHEN 3 THEN N'InProgress' WHEN 4 THEN N'Idle' WHEN 5 THEN N'Retry' WHEN 6 THEN N'Failed' ELSE CONVERT(NVARCHAR(60), h.runstatus) END,
        h.time,
        h.duration,
        h.delivered_commands,
        TRY_CONVERT(DECIMAL(18,2), h.delivery_rate),
        h.error_id,
        e.error_code,
        e.error_text,
        h.comments
    FROM dbo.MSdistribution_agents AS a
    LEFT JOIN LatestHistory AS h
        ON h.agent_id = a.id
       AND h.rn = 1
    LEFT JOIN dbo.MSsubscriber_info AS si
        ON si.subscriber_id = a.subscriber_id
    LEFT JOIN dbo.MSrepl_errors AS e
        ON e.id = h.error_id;
END;

IF OBJECT_ID(N'dbo.MSsnapshot_agents', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MSsnapshot_history', N'U') IS NOT NULL
BEGIN
    ;WITH LatestHistory AS
    (
        SELECT
            h.*,
            ROW_NUMBER() OVER (PARTITION BY h.agent_id ORDER BY h.time DESC) AS rn
        FROM dbo.MSsnapshot_history AS h
    )
    INSERT INTO #ReplicationAgentStatus
    SELECT
        @@SERVERNAME,
        a.publisher_db,
        a.publication,
        N'Snapshot',
        a.name,
        NULL,
        NULL,
        h.runstatus,
        CASE h.runstatus WHEN 1 THEN N'Started' WHEN 2 THEN N'Succeeded' WHEN 3 THEN N'InProgress' WHEN 4 THEN N'Idle' WHEN 5 THEN N'Retry' WHEN 6 THEN N'Failed' ELSE CONVERT(NVARCHAR(60), h.runstatus) END,
        h.time,
        h.duration,
        NULL,
        NULL,
        h.error_id,
        e.error_code,
        e.error_text,
        h.comments
    FROM dbo.MSsnapshot_agents AS a
    LEFT JOIN LatestHistory AS h
        ON h.agent_id = a.id
       AND h.rn = 1
    LEFT JOIN dbo.MSrepl_errors AS e
        ON e.id = h.error_id;
END;

IF OBJECT_ID(N'dbo.MSmerge_agents', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MSmerge_history', N'U') IS NOT NULL
BEGIN
    ;WITH LatestHistory AS
    (
        SELECT
            h.*,
            ROW_NUMBER() OVER (PARTITION BY h.agent_id ORDER BY h.time DESC) AS rn
        FROM dbo.MSmerge_history AS h
    )
    INSERT INTO #ReplicationAgentStatus
    SELECT
        @@SERVERNAME,
        a.publisher_db,
        a.publication,
        N'Merge',
        a.name,
        COALESCE(si.name, CONVERT(NVARCHAR(256), a.subscriber_id)),
        a.subscriber_db,
        h.runstatus,
        CASE h.runstatus WHEN 1 THEN N'Started' WHEN 2 THEN N'Succeeded' WHEN 3 THEN N'InProgress' WHEN 4 THEN N'Idle' WHEN 5 THEN N'Retry' WHEN 6 THEN N'Failed' ELSE CONVERT(NVARCHAR(60), h.runstatus) END,
        h.time,
        h.duration,
        NULL,
        NULL,
        h.error_id,
        e.error_code,
        e.error_text,
        h.comments
    FROM dbo.MSmerge_agents AS a
    LEFT JOIN LatestHistory AS h
        ON h.agent_id = a.id
       AND h.rn = 1
    LEFT JOIN dbo.MSsubscriber_info AS si
        ON si.subscriber_id = a.subscriber_id
    LEFT JOIN dbo.MSrepl_errors AS e
        ON e.id = h.error_id;
END;

SELECT *
FROM #ReplicationAgentStatus
ORDER BY database_name, publication, agent_type, agent_name;
"@

Write-Host "Collecting replication health from $ServerName..."
$databaseFlagRows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $databaseFlagQuery)
$inserted = 0

foreach ($row in $databaseFlagRows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertReplicationHealthHistory" -SqlParameter @{
        server_name              = [string]$row.server_name
        database_name            = ConvertTo-NullableValue $row.database_name
        publication              = $null
        agent_type               = "DatabaseFlag"
        agent_name               = $null
        subscriber_name          = $null
        subscriber_database_name = $null
        run_status               = $null
        run_status_desc          = "Configured"
        last_event_time          = $null
        latency_seconds          = $null
        delivered_commands       = $null
        delivery_rate            = $null
        error_id                 = $null
        error_code               = $null
        error_text               = $null
        comments                 = "Database replication flags from sys.databases."
        is_published             = ConvertTo-NullableValue $row.is_published
        is_subscribed            = ConvertTo-NullableValue $row.is_subscribed
        is_merge_published       = ConvertTo-NullableValue $row.is_merge_published
        is_distributor           = ConvertTo-NullableValue $row.is_distributor
    }
    $inserted++
}

$distributionState = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $distributionExistsQuery)
if ($distributionState.Count -eq 0 -or $null -eq (ConvertTo-NullableValue $distributionState[0].distribution_database_id)) {
    Write-Host "No local distribution database found on $ServerName. Inserted $inserted replication database flag rows."
    return
}

$agentRows = @(Invoke-SourceQuery -ServerName $ServerName -Database distribution -Query $agentQuery)

foreach ($row in $agentRows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertReplicationHealthHistory" -SqlParameter @{
        server_name              = [string]$row.server_name
        database_name            = ConvertTo-NullableValue $row.database_name
        publication              = ConvertTo-NullableValue $row.publication
        agent_type               = ConvertTo-NullableValue $row.agent_type
        agent_name               = ConvertTo-NullableValue $row.agent_name
        subscriber_name          = ConvertTo-NullableValue $row.subscriber_name
        subscriber_database_name = ConvertTo-NullableValue $row.subscriber_database_name
        run_status               = ConvertTo-NullableValue $row.run_status
        run_status_desc          = ConvertTo-NullableValue $row.run_status_desc
        last_event_time          = ConvertTo-NullableValue $row.last_event_time
        latency_seconds          = ConvertTo-NullableValue $row.latency_seconds
        delivered_commands       = ConvertTo-NullableValue $row.delivered_commands
        delivery_rate            = ConvertTo-NullableValue $row.delivery_rate
        error_id                 = ConvertTo-NullableValue $row.error_id
        error_code               = ConvertTo-NullableValue $row.error_code
        error_text               = ConvertTo-NullableValue $row.error_text
        comments                 = ConvertTo-NullableValue $row.comments
        is_published             = $null
        is_subscribed            = $null
        is_merge_published       = $null
        is_distributor           = $null
    }
    $inserted++
}

Write-Host "Inserted $inserted replication health rows for $ServerName."
