[CmdletBinding()]
param(
    [switch]$FailOnSourceCollectionFailure
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

$logDirectory = Join-Path $PSScriptRoot "logs"
$transcriptStarted = $false

try {
    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    $transcriptPath = Join-Path $logDirectory ("capacity-collection-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    Start-Transcript -Path $transcriptPath -Append | Out-Null
    $transcriptStarted = $true
}
catch {
    Write-Warning "Could not start transcript logging. $($_.Exception.Message)"
}

try {
    Initialize-DbaTools
    Assert-RepositoryAvailable

    $servers = @(Get-ActiveMonitoredServers)
    if ($servers.Count -eq 0) {
        Write-Warning "No active servers found in dbo.ServerInventory."
        exit 0
    }

    $collectorScripts = @(
        @{ Name = 'DatabaseSize'; Path = Join-Path $PSScriptRoot 'Collect-DatabaseSize.ps1'; SkipFor = @() },
        @{ Name = 'FileSize';     Path = Join-Path $PSScriptRoot 'Collect-FileSize.ps1';     SkipFor = @() },
        @{ Name = 'DiskSpace';    Path = Join-Path $PSScriptRoot 'Collect-DiskSpace.ps1';    SkipFor = @('AzureSQL') },
        @{ Name = 'TableSize';    Path = Join-Path $PSScriptRoot 'Collect-TableSize.ps1';    SkipFor = @() },
        @{ Name = 'BackupSize';   Path = Join-Path $PSScriptRoot 'Collect-BackupSize.ps1';   SkipFor = @('AzureSQL') },
        @{ Name = 'TempDBUsage';  Path = Join-Path $PSScriptRoot 'Collect-TempDBUsage.ps1';  SkipFor = @('AzureSQL') },
        @{ Name = 'LongRunningTransactions'; Path = Join-Path $PSScriptRoot 'Collect-LongRunningTransactions.ps1'; SkipFor = @('AzureSQL') },
        @{ Name = 'BlockingSessions'; Path = Join-Path $PSScriptRoot 'Collect-BlockingSessions.ps1'; SkipFor = @('AzureSQL') },
        @{ Name = 'AlwaysOnHealth'; Path = Join-Path $PSScriptRoot 'Collect-AlwaysOnHealth.ps1'; SkipFor = @('AzureSQL') },
        @{ Name = 'ReplicationHealth'; Path = Join-Path $PSScriptRoot 'Collect-ReplicationHealth.ps1'; SkipFor = @('AzureSQL') }
    )

    $failureCount = 0
    $successfulMetricCount = 0

    foreach ($server in $servers) {
        $serverName = [string]$server.server_name
        $serverType = [string]$server.server_type
        $connectionMode = [string]$server.connection_mode
        $credentialKey = [string]$server.credential_key

        if ([string]::IsNullOrWhiteSpace($connectionMode)) {
            $connectionMode = Get-SqlAuthMode
        }

        if ([string]::IsNullOrWhiteSpace($credentialKey)) {
            $credentialKey = "default"
        }

        Write-Host "Starting collection for $serverName ($serverType, $connectionMode, credential key: $credentialKey)..."

        foreach ($collector in $collectorScripts) {
            if ($collector.SkipFor -contains $serverType) {
                Write-Host "Skipping $($collector.Name) for $serverName because server_type '$serverType' is not supported by that collector."
                continue
            }

            try {
                $env:DBA_SOURCE_SERVER_TYPE = $serverType
                $env:DBA_SOURCE_CONNECTION_MODE = $connectionMode
                $env:DBA_SOURCE_CREDENTIAL_KEY = $credentialKey
                & $collector.Path -ServerName $serverName
                $successfulMetricCount++
            }
            catch {
                $failureCount++
                Write-Warning "$($collector.Name) failed for $serverName. $($_.Exception.Message)"
                Write-CollectionFailureAlert -ServerName $serverName -DatabaseName $null -MetricName $collector.Name -Message $_.Exception.Message
            }
            finally {
                Remove-Item Env:\DBA_SOURCE_SERVER_TYPE -ErrorAction SilentlyContinue
                Remove-Item Env:\DBA_SOURCE_CONNECTION_MODE -ErrorAction SilentlyContinue
                Remove-Item Env:\DBA_SOURCE_CREDENTIAL_KEY -ErrorAction SilentlyContinue
            }
        }
    }

    if ($successfulMetricCount -eq 0) {
        throw "No metric collectors completed successfully for any active server."
    }

    & (Join-Path $PSScriptRoot 'Run-Forecast.ps1')

    if ($failureCount -gt 0) {
        Write-Warning "$failureCount collector task(s) failed. Successful metric groups: $successfulMetricCount."
    }

    if ($FailOnSourceCollectionFailure -and $failureCount -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    Write-Error "Capacity collection pipeline failed. $($_.Exception.Message)"
    exit 1
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
