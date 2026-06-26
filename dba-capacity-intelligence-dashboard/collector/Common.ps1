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

function Get-SourceCredentialFromEnvironment {
    [CmdletBinding()]
    param(
        [string]$CredentialKey
    )

    $normalizedKey = if ([string]::IsNullOrWhiteSpace($CredentialKey) -or $CredentialKey -like '$(*') { "default" } else { $CredentialKey }

    if (-not [string]::IsNullOrWhiteSpace($env:SOURCE_SQL_CREDENTIALS_JSON) -and $env:SOURCE_SQL_CREDENTIALS_JSON -notlike '$(*') {
        try {
            $credentialMap = $env:SOURCE_SQL_CREDENTIALS_JSON | ConvertFrom-Json
        }
        catch {
            throw "SOURCE_SQL_CREDENTIALS_JSON is not valid JSON. $($_.Exception.Message)"
        }

        $credentialProperty = $credentialMap.PSObject.Properties[$normalizedKey]

        if ($credentialProperty) {
            $credential = $credentialProperty.Value
            $userProperty = $credential.PSObject.Properties["user"]
            $usernameProperty = $credential.PSObject.Properties["username"]
            $passwordProperty = $credential.PSObject.Properties["password"]
            $user = if ($userProperty) { $userProperty.Value } elseif ($usernameProperty) { $usernameProperty.Value } else { $null }
            $password = if ($passwordProperty) { $passwordProperty.Value } else { $null }

            if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($password)) {
                return [pscustomobject]@{
                    User = [string]$user
                    Password = [string]$password
                    Key = $normalizedKey
                }
            }
        }
    }

    if ($normalizedKey -eq "default") {
        if (-not [string]::IsNullOrWhiteSpace($env:SQL_USER) -and -not [string]::IsNullOrWhiteSpace($env:SQL_PASSWORD)) {
            return [pscustomobject]@{
                User = $env:SQL_USER
                Password = $env:SQL_PASSWORD
                Key = $normalizedKey
            }
        }
    }

    throw "No source SQL credential found for key '$normalizedKey'. Add it to SOURCE_SQL_CREDENTIALS_JSON or use key 'default' with SQL_USER/SQL_PASSWORD."
}

function Get-SqlAuthMode {
    [CmdletBinding()]
    param(
        [string]$PreferredMode
    )

    $authMode = $PreferredMode

    if ([string]::IsNullOrWhiteSpace($authMode) -or $authMode -like '$(*') {
        $authMode = $env:DBA_SQL_AUTH_MODE
    }

    if ([string]::IsNullOrWhiteSpace($authMode) -or $authMode -like '$(*') {
        return "SqlAuth"
    }

    if ($authMode -notin @("SqlAuth", "WindowsAuth")) {
        throw "DBA_SQL_AUTH_MODE must be either 'SqlAuth' or 'WindowsAuth'. Current value: $authMode"
    }

    return $authMode
}

function New-SourceSqlConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$AuthMode,

        [string]$CredentialKey
    )

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = $ServerName
    $builder["Initial Catalog"] = $Database
    $builder["Encrypt"] = $true
    $builder["TrustServerCertificate"] = $true
    $builder["Connection Timeout"] = 30

    if ($AuthMode -eq "SqlAuth") {
        $credential = Get-SourceCredentialFromEnvironment -CredentialKey $CredentialKey
        $builder["User ID"] = $credential.User
        $builder["Password"] = $credential.Password
    }
    elseif ($AuthMode -eq "WindowsAuth") {
        $builder["Integrated Security"] = $true
    }
    else {
        throw "Source connection mode '$AuthMode' is not implemented by the MVP collector."
    }

    $builder.ConnectionString
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

    # Source SQL Servers can use a different connection mode from the local
    # DBAUtility repository. The value comes from ServerInventory.connection_mode.
    $authMode = Get-SqlAuthMode -PreferredMode $env:DBA_SOURCE_CONNECTION_MODE
    $connectionString = New-SourceSqlConnectionString -ServerName $ServerName -Database $Database -AuthMode $authMode -CredentialKey $env:DBA_SOURCE_CREDENTIAL_KEY
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
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        return $table.Rows
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
        $command.Dispose()
    }
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
    connection_mode,
    credential_key
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
