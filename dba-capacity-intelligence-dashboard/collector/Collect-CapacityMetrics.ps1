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
        @{ Name = 'DatabaseSize'; Path = Join-Path $PSScriptRoot 'Collect-DatabaseSize.ps1' },
        @{ Name = 'FileSize';     Path = Join-Path $PSScriptRoot 'Collect-FileSize.ps1' },
        @{ Name = 'DiskSpace';    Path = Join-Path $PSScriptRoot 'Collect-DiskSpace.ps1' },
        @{ Name = 'TableSize';    Path = Join-Path $PSScriptRoot 'Collect-TableSize.ps1' },
        @{ Name = 'BackupSize';   Path = Join-Path $PSScriptRoot 'Collect-BackupSize.ps1' },
        @{ Name = 'TempDBUsage';  Path = Join-Path $PSScriptRoot 'Collect-TempDBUsage.ps1' }
    )

    $failureCount = 0
    $successfulMetricCount = 0

    foreach ($server in $servers) {
        $serverName = [string]$server.server_name
        Write-Host "Starting collection for $serverName..."

        foreach ($collector in $collectorScripts) {
            try {
                & $collector.Path -ServerName $serverName
                $successfulMetricCount++
            }
            catch {
                $failureCount++
                Write-Warning "$($collector.Name) failed for $serverName. $($_.Exception.Message)"
                Write-CollectionFailureAlert -ServerName $serverName -DatabaseName $null -MetricName $collector.Name -Message $_.Exception.Message
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
