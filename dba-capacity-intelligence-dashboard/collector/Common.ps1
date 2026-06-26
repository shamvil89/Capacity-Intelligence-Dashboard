# Shared collector utilities. This script intentionally reads credentials only from
# environment variables so secrets do not need to be stored in source control.

Set-StrictMode -Version Latest

function Initialize-DbaTools {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        Write-Host "dbatools module not found. Installing for current user..."
        try {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not mark PSGallery as trusted. Continuing with module installation. $($_.Exception.Message)"
        }

        Install-Module dbatools -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -Confirm:$false -ErrorAction Stop
    }

    Import-Module dbatools -ErrorAction Stop
}

function New-SqlCredentialFromEnvironment {
    [CmdletBinding()]
    param()

    $user = $env:SQL_USER
    $password = $env:SQL_PASSWORD

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($password)) {
        throw "SQL_USER and SQL_PASSWORD environment variables are required for MVP SQL authentication."
    }

    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    [pscredential]::new($user, $securePassword)
}

function Get-SqlAuthMode {
    [CmdletBinding()]
    param()

    $authMode = $env:DBA_SQL_AUTH_MODE

    if ([string]::IsNullOrWhiteSpace($authMode) -or $authMode -like '$(*') {
        return "SqlAuth"
    }

    if ($authMode -notin @("SqlAuth", "WindowsAuth")) {
        throw "DBA_SQL_AUTH_MODE must be either 'SqlAuth' or 'WindowsAuth'. Current value: $authMode"
    }

    return $authMode
}

function Get-RepositoryConfig {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:DBA_REPOSITORY_SERVER)) {
        throw "DBA_REPOSITORY_SERVER environment variable is required."
    }

    if ([string]::IsNullOrWhiteSpace($env:DBA_REPOSITORY_DB)) {
        throw "DBA_REPOSITORY_DB environment variable is required."
    }

    [pscustomobject]@{
        Server   = $env:DBA_REPOSITORY_SERVER
        Database = $env:DBA_REPOSITORY_DB
        AuthMode = Get-SqlAuthMode
    }
}

function Invoke-RepositoryQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [hashtable]$SqlParameter = @{}
    )

    $repository = Get-RepositoryConfig
    $invokeParams = @{
        SqlInstance   = $repository.Server
        Database      = $repository.Database
        Query         = $Query
        QueryTimeout  = 0
        EnableException = $true
        AppendConnectionString = "TrustServerCertificate=True"
    }

    if ($repository.AuthMode -eq "SqlAuth") {
        $invokeParams.SqlCredential = New-SqlCredentialFromEnvironment
    }

    if ($SqlParameter.Count -gt 0) {
        $invokeParams.SqlParameter = $SqlParameter
    }

    Invoke-DbaQuery @invokeParams
}

function Invoke-SourceQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [hashtable]$SqlParameter = @{}
    )

    # MVP supports one authentication mode for all connections. TODO: add
    # Managed Identity and per-server credentials based on ServerInventory.
    $authMode = Get-SqlAuthMode

    $invokeParams = @{
        SqlInstance   = $ServerName
        Database      = $Database
        Query         = $Query
        QueryTimeout  = 0
        EnableException = $true
        AppendConnectionString = "TrustServerCertificate=True"
    }

    if ($authMode -eq "SqlAuth") {
        $invokeParams.SqlCredential = New-SqlCredentialFromEnvironment
    }

    if ($SqlParameter.Count -gt 0) {
        $invokeParams.SqlParameter = $SqlParameter
    }

    Invoke-DbaQuery @invokeParams
}

function Invoke-RepositoryProcedure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcedureName,

        [Parameter(Mandatory = $true)]
        [hashtable]$SqlParameter
    )

    $assignments = $SqlParameter.Keys | ForEach-Object { "@$_ = @$_" }
    $query = "EXEC $ProcedureName $($assignments -join ', ');"
    Invoke-RepositoryQuery -Query $query -SqlParameter $SqlParameter | Out-Null
}

function Get-ActiveMonitoredServers {
    [CmdletBinding()]
    param()

    $query = @"
SELECT
    server_name,
    environment,
    server_type,
    connection_mode
FROM dbo.ServerInventory
WHERE is_active = 1
ORDER BY server_name;
"@

    Invoke-RepositoryQuery -Query $query
}

function Assert-RepositoryAvailable {
    [CmdletBinding()]
    param()

    Invoke-RepositoryQuery -Query "SELECT 1 AS repository_available;" | Out-Null
}

function ConvertTo-NullableValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    return $Value
}

function Limit-AlertMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Message.Length -le 1900) {
        return $Message
    }

    return $Message.Substring(0, 1900)
}

function Write-CollectionFailureAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [AllowNull()]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [string]$MetricName,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $alertMessage = Limit-AlertMessage -Message "Collection failed for $MetricName. $Message"
    $query = @"
DECLARE @today DATETIME2(7) = CONVERT(DATE, SYSUTCDATETIME());
DECLARE @tomorrow DATETIME2(7) = DATEADD(DAY, 1, @today);

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.AlertHistory
    WHERE alert_time >= @today
      AND alert_time < @tomorrow
      AND server_name = @server_name
      AND ISNULL(database_name, N'') = ISNULL(@database_name, N'')
      AND alert_type = @alert_type
)
BEGIN
    INSERT INTO dbo.AlertHistory
    (
        server_name,
        database_name,
        alert_type,
        severity,
        message
    )
    VALUES
    (
        @server_name,
        @database_name,
        @alert_type,
        'High',
        @message
    );
END;
"@

    Invoke-RepositoryQuery -Query $query -SqlParameter @{
        server_name   = $ServerName
        database_name = $DatabaseName
        alert_type    = "CollectionFailure:$MetricName"
        message       = $alertMessage
    } | Out-Null
}
