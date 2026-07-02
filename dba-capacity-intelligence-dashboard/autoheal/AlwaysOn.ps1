[CmdletBinding()]
param()

function ConvertTo-SqlIdentifier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    "[$($Name.Replace(']', ']]'))]"
}

function ConvertTo-JsonSafeValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToString('o')
    }

    $Value
}

function Convert-DataRowsToObjects {
    param([AllowNull()][object[]]$Rows)

    $items = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) {
            continue
        }

        $item = [ordered]@{}
        foreach ($column in $row.Table.Columns) {
            $item[$column.ColumnName] = ConvertTo-JsonSafeValue $row[$column.ColumnName]
        }

        $items += [pscustomobject]$item
    }

    $items
}

function Invoke-SourceNonQueryForAutoHeal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetServerName,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [hashtable]$SqlParameter = @{}
    )

    $authMode = Get-SqlConnectionMode -PreferredMode $env:DBA_SOURCE_CONNECTION_MODE
    $connectionString = New-SourceSqlConnectionString -ServerName $TargetServerName -Database $Database -AuthMode $authMode -CredentialKey $env:DBA_SOURCE_CREDENTIAL_KEY
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = 0

    foreach ($key in $SqlParameter.Keys) {
        $parameter = $command.Parameters.Add("@$key", [System.Data.SqlDbType]::NVarChar, 4000)
        $parameter.Value = $SqlParameter[$key]
    }

    try {
        $connection.Open()
        [void]$command.ExecuteNonQuery()
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
        $command.Dispose()
    }
}

function Invoke-AlwaysOnSourceQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetServerName,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [hashtable]$SqlParameter = @{}
    )

    try {
        Convert-DataRowsToObjects @(Invoke-SourceQuery -ServerName $TargetServerName -Database master -Query $Query -SqlParameter $SqlParameter)
    }
    catch {
        [pscustomobject]@{
            queryFailed = $true
            errorMessage = $_.Exception.Message
        }
    }
}

function Get-AutoHealAlertContext {
    $query = @"
SELECT TOP (1)
    request.alert_id,
    request.alert_type,
    request.server_name,
    request.database_name,
    alert.details_json
FROM dbo.AutoHealRequest AS request
LEFT JOIN dbo.AlertHistory AS alert
    ON alert.alert_id = request.alert_id
WHERE request.request_id = CONVERT(uniqueidentifier, @request_id);
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{ request_id = $RequestId.ToString() })
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            AlertId = $null
            AlertType = $null
            Details = $null
        }
    }

    $details = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$rows[0].details_json)) {
        try {
            $details = [string]$rows[0].details_json | ConvertFrom-Json
        }
        catch {
            $details = $null
        }
    }

    [pscustomobject]@{
        AlertId = ConvertTo-SqlNumber $rows[0].alert_id
        AlertType = ConvertTo-SqlText $rows[0].alert_type
        RequestServerName = ConvertTo-SqlText $rows[0].server_name
        RequestDatabaseName = ConvertTo-SqlText $rows[0].database_name
        Details = $details
    }
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($property) {
        return $property.Value
    }

    $null
}

function Get-AlertDatabaseTargets {
    param([AllowNull()][object]$Details)

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($DatabaseName, (Get-PropertyValue -Object $Details -PropertyName 'databaseName'))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $targets.Add([string]$value)
        }
    }

    foreach ($collectionName in @('databaseIssues', 'alwaysOnEvidence')) {
        $collection = Get-PropertyValue -Object $Details -PropertyName $collectionName
        foreach ($item in @($collection)) {
            $database = Get-PropertyValue -Object $item -PropertyName 'databaseName'
            if (-not [string]::IsNullOrWhiteSpace([string]$database)) {
                $targets.Add([string]$database)
            }
        }
    }

    $targets | Select-Object -Unique
}

function Get-ComputerNameFromSqlInstance {
    param([Parameter(Mandatory = $true)][string]$SqlInstance)

    ($SqlInstance -split '\\')[0] -split ',' | Select-Object -First 1
}

function Get-SqlServiceHealth {
    param([Parameter(Mandatory = $true)][string]$TargetServerName)

    $computerName = Get-ComputerNameFromSqlInstance -SqlInstance $TargetServerName
    try {
        $services = @(Get-CimInstance -ClassName Win32_Service -ComputerName $computerName -Filter "Name LIKE 'MSSQL%'" -ErrorAction Stop)
        $services |
            Where-Object { $_.Name -like 'MSSQL*' -or $_.Name -like 'SQLAgent*' } |
            Select-Object Name, DisplayName, State, StartMode, StartName |
            ForEach-Object {
                [pscustomobject]@{
                    name = $_.Name
                    displayName = $_.DisplayName
                    state = $_.State
                    startMode = $_.StartMode
                    startName = $_.StartName
                }
            }
    }
    catch {
        @([pscustomobject]@{
            checkFailed = $true
            computerName = $computerName
            errorMessage = $_.Exception.Message
        })
    }
}

function Get-ClusterHealth {
    param([Parameter(Mandatory = $true)][string]$TargetServerName)

    $computerName = Get-ComputerNameFromSqlInstance -SqlInstance $TargetServerName
    $result = [ordered]@{
        computerName = $computerName
        moduleAvailable = $false
        nodes = @()
        groups = @()
        resources = @()
        quorum = $null
        errorMessage = $null
    }

    if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
        $result.errorMessage = 'FailoverClusters PowerShell module is not installed on this agent.'
        return [pscustomobject]$result
    }

    try {
        Import-Module FailoverClusters -ErrorAction Stop
        $result.moduleAvailable = $true
        $result.nodes = @(Get-ClusterNode -Cluster $computerName -ErrorAction Stop | Select-Object Name, State)
        $result.groups = @(Get-ClusterGroup -Cluster $computerName -ErrorAction Stop | Select-Object Name, State, OwnerNode)
        $result.resources = @(Get-ClusterResource -Cluster $computerName -ErrorAction Stop | Select-Object Name, ResourceType, State, OwnerGroup)
        $result.quorum = Get-ClusterQuorum -Cluster $computerName -ErrorAction Stop | Select-Object QuorumResource, QuorumType
    }
    catch {
        $result.errorMessage = $_.Exception.Message
    }

    [pscustomobject]$result
}

function Get-EndpointConnectivity {
    param([AllowNull()][object[]]$EndpointUrls)

    $results = @()
    foreach ($row in @($EndpointUrls)) {
        $endpointUrl = [string](Get-PropertyValue -Object $row -PropertyName 'endpoint_url')
        if ([string]::IsNullOrWhiteSpace($endpointUrl)) {
            continue
        }

        try {
            $uri = [uri]$endpointUrl
            $port = if ($uri.Port -gt 0) { $uri.Port } else { 5022 }
            $reachable = Test-NetConnection -ComputerName $uri.Host -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
            $results += [pscustomobject]@{
                replicaServerName = Get-PropertyValue -Object $row -PropertyName 'replica_server_name'
                endpointUrl = $endpointUrl
                host = $uri.Host
                port = $port
                reachable = [bool]$reachable
            }
        }
        catch {
            $results += [pscustomobject]@{
                replicaServerName = Get-PropertyValue -Object $row -PropertyName 'replica_server_name'
                endpointUrl = $endpointUrl
                reachable = $false
                errorMessage = $_.Exception.Message
            }
        }
    }

    $results
}

function Get-AlwaysOnRecommendations {
    param(
        [AllowNull()][object[]]$ReplicaRows,
        [AllowNull()][object[]]$DatabaseRows,
        [AllowNull()][object[]]$EndpointRows,
        [AllowNull()][object[]]$ConnectivityRows,
        [AllowNull()][object[]]$AttemptedActions,
        [bool]$HadrEnabled
    )

    $recommendations = New-Object System.Collections.Generic.List[string]

    if (-not $HadrEnabled) {
        $recommendations.Add('Always On is not enabled on this SQL Server instance. Enable Always On Availability Groups in SQL Server Configuration Manager and restart the SQL Server service during an approved window.')
    }

    if (@($EndpointRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -and (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -ne 'STARTED' }).Count -gt 0) {
        $recommendations.Add('One or more database mirroring endpoints are not STARTED. Auto-heal attempts to start stopped endpoints; if they stop again, check endpoint ownership, permissions, and SQL error log entries.')
    }

    if (@($ConnectivityRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'reachable') -eq $false }).Count -gt 0) {
        $recommendations.Add('Endpoint connectivity failed for at least one replica. Verify DNS, firewall rules, the actual endpoint port from sys.database_mirroring_endpoints/sys.availability_replicas, and SQL service account CONNECT permission on the endpoint.')
    }

    if (@($ReplicaRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'connected_state_desc') -and (Get-PropertyValue -Object $_ -PropertyName 'connected_state_desc') -ne 'CONNECTED' }).Count -gt 0) {
        $recommendations.Add('At least one replica is disconnected. Check SQL Server service status on that replica, endpoint status, endpoint port connectivity, and HADR errors in the SQL Server error log.')
    }

    if (@($DatabaseRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'is_suspended') -eq $true -or (Get-PropertyValue -Object $_ -PropertyName 'is_suspended') -eq 1 }).Count -gt 0) {
        $recommendations.Add('One or more databases are suspended. Auto-heal attempts ALTER DATABASE SET HADR RESUME for the affected database rows; if suspension returns, fix the underlying disk, endpoint, network, or secondary database issue.')
    }

    if (@($DatabaseRows | Where-Object {
        $value = Get-PropertyValue -Object $_ -PropertyName 'log_send_queue_size_kb'
        $null -ne $value -and [decimal]$value -gt 0
    }).Count -gt 0) {
        $recommendations.Add('Log send queue is present. Check heavy primary workload, primary log disk latency, endpoint/network latency, and whether the secondary replica is connected.')
    }

    if (@($DatabaseRows | Where-Object {
        $value = Get-PropertyValue -Object $_ -PropertyName 'redo_queue_size_kb'
        $null -ne $value -and [decimal]$value -gt 0
    }).Count -gt 0) {
        $recommendations.Add('Redo queue is present. Check secondary CPU, secondary data/log disk latency, blocking or long-running reporting queries on the secondary, and redo rate.')
    }

    if (@($ReplicaRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'last_connect_error_number' }).Count -gt 0) {
        $recommendations.Add('Replica connect errors were captured. Review SQL error log HADR/endpoint entries and Windows cluster logs around the last connect error timestamp.')
    }

    if (@($AttemptedActions).Count -eq 0) {
        $recommendations.Add('No low-risk automatic repair was available. Do not force failover, change availability mode, or modify quorum/session timeout without DBA/business approval.')
    }

    $recommendations | Select-Object -Unique
}

function Invoke-AlwaysOnHealthAssessment {
    Set-AutoHealRequestStatus -Status 'Running' -Message "Assessing Always On health for $ServerName." -DetailsJson $null

    Set-SourceConnectionEnvironment

    $alertContext = Get-AutoHealAlertContext
    $details = $alertContext.Details
    $availabilityGroupName = [string](Get-PropertyValue -Object $details -PropertyName 'availabilityGroupName')
    if ([string]::IsNullOrWhiteSpace($availabilityGroupName)) {
        $firstEvidence = @((Get-PropertyValue -Object $details -PropertyName 'alwaysOnEvidence')) | Select-Object -First 1
        $availabilityGroupName = [string](Get-PropertyValue -Object $firstEvidence -PropertyName 'availabilityGroupName')
    }

    $databaseTargets = @(Get-AlertDatabaseTargets -Details $details)
    $attemptedActions = @()
    $skippedActions = @()
    $queryFailures = @()

    $hadrRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query "SELECT CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) AS is_hadr_enabled;")
    if ($hadrRows.Count -gt 0 -and (Get-PropertyValue -Object $hadrRows[0] -PropertyName 'queryFailed')) {
        throw "Could not check Always On enabled state. $(Get-PropertyValue -Object $hadrRows[0] -PropertyName 'errorMessage')"
    }

    $isHadrEnabled = $hadrRows.Count -gt 0 -and [int](Get-PropertyValue -Object $hadrRows[0] -PropertyName 'is_hadr_enabled') -eq 1

    if (-not $isHadrEnabled) {
        $detailsJson = [ordered]@{
            action = 'AlwaysOnHealthAssessment'
            serverName = $ServerName
            databaseName = $DatabaseName
            hadrEnabled = $false
            recommendations = @(Get-AlwaysOnRecommendations -ReplicaRows @() -DatabaseRows @() -EndpointRows @() -ConnectivityRows @() -AttemptedActions @() -HadrEnabled $false)
        } | ConvertTo-Json -Depth 8 -Compress

        Set-AutoHealRequestStatus -Status 'CompletedWithWarnings' -Message "Always On is not enabled on $ServerName. No automatic repair was attempted." -DetailsJson $detailsJson
        return
    }

    $replicaQuery = @"
SELECT
    ag.name AS availability_group_name,
    ar.replica_server_name,
    ars.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.session_timeout,
    ars.last_connect_error_number,
    ars.last_connect_error_description,
    ars.last_connect_error_timestamp
FROM sys.availability_groups AS ag
INNER JOIN sys.availability_replicas AS ar
    ON ar.group_id = ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
    ON ars.group_id = ar.group_id
   AND ars.replica_id = ar.replica_id
WHERE (@availability_group_name = N'' OR ag.name = @availability_group_name)
ORDER BY ag.name, ar.replica_server_name;
"@

    $databaseQuery = @"
SELECT
    ag.name AS availability_group_name,
    ar.replica_server_name,
    DB_NAME(drs.database_id) AS database_name,
    drs.is_local,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
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
    drs.last_commit_time
FROM sys.availability_groups AS ag
INNER JOIN sys.availability_replicas AS ar
    ON ar.group_id = ag.group_id
INNER JOIN sys.dm_hadr_database_replica_states AS drs
    ON drs.group_id = ar.group_id
   AND drs.replica_id = ar.replica_id
WHERE (@availability_group_name = N'' OR ag.name = @availability_group_name)
ORDER BY ag.name, ar.replica_server_name, database_name;
"@

    $endpointQuery = @"
SELECT
    e.name AS endpoint_name,
    e.state_desc,
    e.role_desc,
    t.port AS endpoint_port
FROM sys.database_mirroring_endpoints AS e
INNER JOIN sys.tcp_endpoints AS t
    ON e.endpoint_id = t.endpoint_id
ORDER BY e.name;
"@

    $endpointUrlQuery = @"
SELECT
    ag.name AS availability_group_name,
    ar.replica_server_name,
    ar.endpoint_url,
    ar.availability_mode_desc,
    ar.failover_mode_desc
FROM sys.availability_groups AS ag
INNER JOIN sys.availability_replicas AS ar
    ON ar.group_id = ag.group_id
WHERE (@availability_group_name = N'' OR ag.name = @availability_group_name)
ORDER BY ag.name, ar.replica_server_name;
"@

    $sqlErrorQuery = @"
CREATE TABLE #AlwaysOnLog
(
    LogDate DATETIME NULL,
    ProcessInfo NVARCHAR(100) NULL,
    [Text] NVARCHAR(MAX) NULL
);

BEGIN TRY
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'HADR';
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'Always On';
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'endpoint';
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'lease';
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'failover';
    INSERT INTO #AlwaysOnLog EXEC xp_readerrorlog 0, 1, N'suspended';
END TRY
BEGIN CATCH
END CATCH;

SELECT TOP (40)
    LogDate AS log_date,
    ProcessInfo AS process_info,
    [Text] AS log_text
FROM #AlwaysOnLog
WHERE LogDate >= DATEADD(HOUR, -24, GETDATE())
ORDER BY LogDate DESC;
"@

    $sqlParams = @{ availability_group_name = if ([string]::IsNullOrWhiteSpace($availabilityGroupName)) { '' } else { $availabilityGroupName } }

    $replicaRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query $replicaQuery -SqlParameter $sqlParams)
    $databaseRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query $databaseQuery -SqlParameter $sqlParams)
    $endpointRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query $endpointQuery)
    $endpointUrlRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query $endpointUrlQuery -SqlParameter $sqlParams)
    $sqlErrorRows = @(Invoke-AlwaysOnSourceQuery -TargetServerName $ServerName -Query $sqlErrorQuery)

    $queryFailures += @($replicaRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'queryFailed' } | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'errorMessage' })
    $queryFailures += @($databaseRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'queryFailed' } | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'errorMessage' })
    $queryFailures += @($endpointRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'queryFailed' } | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'errorMessage' })
    $queryFailures += @($endpointUrlRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'queryFailed' } | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'errorMessage' })
    $queryFailures += @($sqlErrorRows | Where-Object { Get-PropertyValue -Object $_ -PropertyName 'queryFailed' } | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'errorMessage' })

    $replicaRows = @($replicaRows | Where-Object { -not (Get-PropertyValue -Object $_ -PropertyName 'queryFailed') })
    $databaseRows = @($databaseRows | Where-Object { -not (Get-PropertyValue -Object $_ -PropertyName 'queryFailed') })
    $endpointRows = @($endpointRows | Where-Object { -not (Get-PropertyValue -Object $_ -PropertyName 'queryFailed') })
    $endpointUrlRows = @($endpointUrlRows | Where-Object { -not (Get-PropertyValue -Object $_ -PropertyName 'queryFailed') })
    $sqlErrorRows = @($sqlErrorRows | Where-Object { -not (Get-PropertyValue -Object $_ -PropertyName 'queryFailed') })

    $endpointConnectivity = @(Get-EndpointConnectivity -EndpointUrls $endpointUrlRows)
    $serviceHealth = @(Get-SqlServiceHealth -TargetServerName $ServerName)
    $clusterHealth = Get-ClusterHealth -TargetServerName $ServerName

    foreach ($endpoint in @($endpointRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'endpoint_name') -and (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -and (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -ne 'STARTED' })) {
        $endpointName = [string](Get-PropertyValue -Object $endpoint -PropertyName 'endpoint_name')
        $endpointState = [string](Get-PropertyValue -Object $endpoint -PropertyName 'state_desc')
        try {
            Invoke-SourceNonQueryForAutoHeal -TargetServerName $ServerName -Database master -Query "ALTER ENDPOINT $(ConvertTo-SqlIdentifier -Name $endpointName) STATE = STARTED;"
            $attemptedActions += [pscustomobject]@{
                action = 'StartEndpoint'
                endpointName = $endpointName
                previousState = $endpointState
                status = 'Succeeded'
            }
        }
        catch {
            $attemptedActions += [pscustomobject]@{
                action = 'StartEndpoint'
                endpointName = $endpointName
                previousState = $endpointState
                status = 'Failed'
                errorMessage = $_.Exception.Message
            }
        }
    }

    $suspendedRows = @($databaseRows | Where-Object {
        ((Get-PropertyValue -Object $_ -PropertyName 'is_suspended') -eq $true -or (Get-PropertyValue -Object $_ -PropertyName 'is_suspended') -eq 1) -and
        -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $_ -PropertyName 'database_name')) -and
        (
            $databaseTargets.Count -eq 0 -or
            $databaseTargets -contains [string](Get-PropertyValue -Object $_ -PropertyName 'database_name')
        )
    })

    foreach ($database in @($suspendedRows | ForEach-Object { Get-PropertyValue -Object $_ -PropertyName 'database_name' } | Select-Object -Unique)) {
        try {
            Invoke-SourceNonQueryForAutoHeal -TargetServerName $ServerName -Database master -Query "ALTER DATABASE $(ConvertTo-SqlIdentifier -Name ([string]$database)) SET HADR RESUME;"
            $attemptedActions += [pscustomobject]@{
                action = 'ResumeDataMovement'
                databaseName = [string]$database
                status = 'Succeeded'
            }
        }
        catch {
            $attemptedActions += [pscustomobject]@{
                action = 'ResumeDataMovement'
                databaseName = [string]$database
                status = 'Failed'
                errorMessage = $_.Exception.Message
            }
        }
    }

    if ($suspendedRows.Count -eq 0) {
        $skippedActions += 'No suspended database rows matched the alert target, so ALTER DATABASE SET HADR RESUME was not run.'
    }

    if (@($endpointRows | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -and (Get-PropertyValue -Object $_ -PropertyName 'state_desc') -ne 'STARTED' }).Count -eq 0) {
        $skippedActions += 'No stopped Always On endpoint was found on the connected SQL Server instance.'
    }

    $recommendations = @(Get-AlwaysOnRecommendations `
        -ReplicaRows $replicaRows `
        -DatabaseRows $databaseRows `
        -EndpointRows $endpointRows `
        -ConnectivityRows $endpointConnectivity `
        -AttemptedActions $attemptedActions `
        -HadrEnabled $isHadrEnabled)

    $failedActions = @($attemptedActions | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'status') -eq 'Failed' })
    $successfulActions = @($attemptedActions | Where-Object { (Get-PropertyValue -Object $_ -PropertyName 'status') -eq 'Succeeded' })

    $detailsJson = [ordered]@{
        action = 'AlwaysOnHealthAssessment'
        serverName = $ServerName
        databaseName = $DatabaseName
        availabilityGroupName = if ([string]::IsNullOrWhiteSpace($availabilityGroupName)) { $null } else { $availabilityGroupName }
        hadrEnabled = $isHadrEnabled
        checkedAtUtc = [datetime]::UtcNow.ToString('o')
        replicaHealth = $replicaRows
        databaseHealth = $databaseRows
        endpoints = $endpointRows
        endpointUrls = $endpointUrlRows
        endpointConnectivity = $endpointConnectivity
        sqlServiceHealth = $serviceHealth
        clusterHealth = $clusterHealth
        recentSqlErrorLog = @($sqlErrorRows | Select-Object -First 20)
        attemptedActions = $attemptedActions
        skippedActions = $skippedActions
        queryFailures = $queryFailures
        recommendations = $recommendations
        guardrails = @(
            'Auto-heal does not force failover or allow data loss.',
            'Auto-heal does not change availability mode, failover mode, quorum, firewall rules, endpoint permissions, or session timeout.',
            'Manual DBA approval is still required for failover, quorum, network/firewall, permission, backup/restore, and re-seeding actions.'
        )
    } | ConvertTo-Json -Depth 12 -Compress

    if ($failedActions.Count -gt 0) {
        Set-AutoHealRequestStatus -Status 'CompletedWithWarnings' -Message "Always On assessment completed, but $($failedActions.Count) safe repair action(s) failed. Review result details." -DetailsJson $detailsJson
        return
    }

    if ($successfulActions.Count -gt 0) {
        Set-AutoHealRequestStatus -Status 'Completed' -Message "Always On assessment completed. Applied $($successfulActions.Count) safe repair action(s). Rerun collection to confirm alert retirement." -DetailsJson $detailsJson
        return
    }

    Set-AutoHealRequestStatus -Status 'CompletedWithWarnings' -Message "Always On assessment completed. No safe automatic repair was available; review recommendations." -DetailsJson $detailsJson
}
