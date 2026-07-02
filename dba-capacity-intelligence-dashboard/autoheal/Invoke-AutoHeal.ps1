[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('BackupRetentionScan', 'DeleteSelectedBackupFiles', 'LogShrinkAssessment', 'AlwaysOnHealthAssessment')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [guid]$RequestId,

    [Parameter(Mandatory = $true)]
    [string]$ServerName,

    [string]$DatabaseName,

    [string]$TargetPath,

    [int]$RetentionDays = 90
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\collector\Common.ps1"
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\AlwaysOn.ps1"
. "$PSScriptRoot\BackupRetention.ps1"
. "$PSScriptRoot\LogShrink.ps1"

Initialize-DbaTools

if ($ServerName -eq '__REQUIRED__') {
    throw "ServerName is required. This pipeline is normally queued by the DBA Capacity API."
}

if ($RequestId -eq [guid]::Empty) {
    throw "RequestId is required. This pipeline is normally queued by the DBA Capacity API."
}

if ($DatabaseName -in @('__NONE__', '__AUTO__', '-')) {
    $DatabaseName = ''
}

if ($TargetPath -in @('__AUTO__', '__NONE__', '-')) {
    $TargetPath = ''
}

try {
    switch ($Action) {
        'BackupRetentionScan' {
            Invoke-BackupRetentionScan
        }
        'DeleteSelectedBackupFiles' {
            Invoke-SelectedFileCleanup
        }
        'LogShrinkAssessment' {
            Invoke-LogShrinkAssessment
        }
        'AlwaysOnHealthAssessment' {
            Invoke-AlwaysOnHealthAssessment
        }
    }
}
catch {
    $details = [ordered]@{
        action = $Action
        serverName = $ServerName
        databaseName = $DatabaseName
        targetPath = $TargetPath
        errorMessage = $_.Exception.Message
    } | ConvertTo-Json -Depth 6 -Compress
    Set-AutoHealRequestStatus -Status 'Failed' -Message "Auto-heal failed. $($_.Exception.Message)" -DetailsJson $details
    throw
}
