[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('BackupRetentionScan', 'DeleteSelectedBackupFiles', 'LogShrinkAssessment')]
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
. "$PSScriptRoot\Common.ps1"

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

function ConvertTo-SqlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    [string]$Value
}

function ConvertTo-SqlNumber {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    $Value
}

function ConvertTo-IsoDateTimeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    ([datetime]$Value).ToString('o')
}

function Get-AlertThresholdDecimal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AlertType,

        [Parameter(Mandatory = $true)]
        [string]$SettingKey,

        [Parameter(Mandatory = $true)]
        [decimal]$DefaultValue
    )

    $query = @"
SELECT TOP (1) setting_value_decimal
FROM dbo.AlertThresholdSetting
WHERE alert_type = @alert_type
  AND setting_key = @setting_key;
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{
        alert_type = $AlertType
        setting_key = $SettingKey
    })

    if ($rows.Count -eq 0 -or $null -eq $rows[0].setting_value_decimal -or $rows[0].setting_value_decimal -is [System.DBNull]) {
        return $DefaultValue
    }

    [decimal]$rows[0].setting_value_decimal
}

function Set-AutoHealRequestStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message,

        [AllowNull()]
        [string]$DetailsJson
    )

    $completedAtExpression = if ($Status -in @('Completed', 'Failed', 'CompletedWithWarnings')) { 'SYSUTCDATETIME()' } else { 'completed_at' }
    $query = @"
UPDATE dbo.AutoHealRequest
SET status = @status,
    message = @message,
    details_json = COALESCE(@details_json, details_json),
    completed_at = $completedAtExpression
WHERE request_id = CONVERT(uniqueidentifier, @request_id);
"@

    Invoke-RepositoryQuery -Query $query -SqlParameter @{
        request_id = $RequestId.ToString()
        status = $Status
        message = $Message
        details_json = $DetailsJson
    } | Out-Null
}

function Add-AutoHealFileCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$Extension,

        [AllowNull()]
        [decimal]$SizeMb,

        [AllowNull()]
        [datetime]$LastWriteTimeUtc,

        [AllowNull()]
        [decimal]$AgeDays,

        [bool]$IsOlderThanRetention,

        [Parameter(Mandatory = $true)]
        [string]$ActionStatus,

        [string]$ErrorMessage
    )

    $query = @"
INSERT INTO dbo.AutoHealFileCandidate
(
    request_id,
    file_path,
    extension,
    size_mb,
    last_write_time_utc,
    age_days,
    is_older_than_retention,
    action_status,
    error_message
)
VALUES
(
    CONVERT(uniqueidentifier, @request_id),
    @file_path,
    @extension,
    @size_mb,
    @last_write_time_utc,
    @age_days,
    @is_older_than_retention,
    @action_status,
    @error_message
);
"@

    Invoke-RepositoryQuery -Query $query -SqlParameter @{
        request_id = $RequestId.ToString()
        file_path = $FilePath
        extension = $Extension
        size_mb = ConvertTo-SqlNumber $SizeMb
        last_write_time_utc = if ($LastWriteTimeUtc) { $LastWriteTimeUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffff') } else { $null }
        age_days = ConvertTo-SqlNumber $AgeDays
        is_older_than_retention = if ($IsOlderThanRetention) { 1 } else { 0 }
        action_status = $ActionStatus
        error_message = ConvertTo-SqlText $ErrorMessage
    } | Out-Null
}

function Get-SourceInventoryRow {
    $query = @"
SELECT TOP (1)
    server_name,
    connection_mode,
    credential_key
FROM dbo.ServerInventory
WHERE is_active = 1
  AND
  (
      server_name = @server_name
      OR LEFT(server_name, CHARINDEX(N'.', server_name + N'.') - 1) = @server_name
      OR server_name = LEFT(@server_name, CHARINDEX(N'.', @server_name + N'.') - 1)
  )
ORDER BY CASE WHEN server_name = @server_name THEN 0 ELSE 1 END;
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{ server_name = $ServerName })
    if ($rows.Count -eq 0) {
        return $null
    }

    $rows[0]
}

function Set-SourceConnectionEnvironment {
    $inventory = Get-SourceInventoryRow
    if ($null -eq $inventory) {
        Write-Warning "ServerInventory row not found for $ServerName. Falling back to default source connection settings."
        return
    }

    $env:DBA_SOURCE_CONNECTION_MODE = [string]$inventory.connection_mode
    $env:DBA_SOURCE_CREDENTIAL_KEY = if ($inventory.credential_key) { [string]$inventory.credential_key } else { 'default' }
}

function Get-ServerHostName {
    param([string]$Name)

    $hostName = $Name.Trim()
    foreach ($prefix in @('tcp:', 'np:', 'lpc:')) {
        if ($hostName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $hostName = $hostName.Substring($prefix.Length)
            break
        }
    }

    if ($hostName.Contains(',')) {
        $hostName = $hostName.Split(',')[0]
    }

    if ($hostName.Contains('\')) {
        $hostName = $hostName.Split('\')[0]
    }

    $hostName.Trim().TrimEnd('.')
}

function Test-IsLocalHostName {
    param([string]$Name)

    $hostName = Get-ServerHostName -Name $Name
    $localNames = @(
        '.',
        'localhost',
        $env:COMPUTERNAME,
        "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $localNames | Where-Object { [string]::Equals($_, $hostName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
}

function Convert-VolumePathToScanPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $trimmedPath = $Path.Trim()
    if ($trimmedPath.StartsWith('\\')) {
        return $trimmedPath
    }

    if (Test-IsLocalHostName -Name $ServerName) {
        return $trimmedPath
    }

    if ($trimmedPath -match '^([a-zA-Z]):\\?(.*)$') {
        $drive = $Matches[1].ToUpperInvariant()
        $suffix = $Matches[2]
        $hostName = Get-ServerHostName -Name $ServerName
        if ([string]::IsNullOrWhiteSpace($suffix)) {
            return "\\$hostName\$drive`$"
        }

        return "\\$hostName\$drive`$\$suffix"
    }

    $trimmedPath
}

function Test-IsWholeDriveRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalizedPath = $Path.Trim().TrimEnd('\')
    $normalizedPath -match '^[a-zA-Z]:$' -or $normalizedPath -match '^\\\\[^\\]+\\[a-zA-Z]\$$'
}

function Test-IsBackupFileExtension {
    param(
        [AllowNull()]
        [string]$Extension
    )

    if ([string]::IsNullOrWhiteSpace($Extension)) {
        return $false
    }

    @('.bak', '.trn') -contains $Extension.ToLowerInvariant()
}

function Test-IsProtectedBackupFileName {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $File.Name -match '(?i)(do[\s._-]*not[\s._-]*delete|keep)'
}

function Get-WholeDriveWindowsDirectoryCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanRoot
    )

    if (-not (Test-IsWholeDriveRoot -Path $ScanRoot)) {
        return 0
    }

    @(
        Get-ChildItem -LiteralPath $ScanRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { [string]::Equals($_.Name, 'Windows', [System.StringComparison]::OrdinalIgnoreCase) }
    ).Count
}

function Get-BackupCandidateFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanRoot
    )

    if (-not (Test-IsWholeDriveRoot -Path $ScanRoot)) {
        Get-ChildItem -LiteralPath $ScanRoot -Recurse -File -Force -ErrorAction SilentlyContinue
        return
    }

    Get-ChildItem -LiteralPath $ScanRoot -File -Force -ErrorAction SilentlyContinue

    foreach ($directory in Get-ChildItem -LiteralPath $ScanRoot -Directory -Force -ErrorAction SilentlyContinue) {
        if ([string]::Equals($directory.Name, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        Get-ChildItem -LiteralPath $directory.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
    }
}

function Get-ScanRoots {
    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        return @(Convert-VolumePathToScanPath -Path $TargetPath)
    }

    $query = @"
WITH latest AS
(
    SELECT
        volume_mount_point,
        ROW_NUMBER() OVER
        (
            PARTITION BY server_name, volume_mount_point
            ORDER BY collection_time DESC, id DESC
        ) AS rn
    FROM dbo.DiskSpaceHistory
    WHERE server_name = @server_name
)
SELECT TOP (10) volume_mount_point
FROM latest
WHERE rn = 1
ORDER BY volume_mount_point;
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{ server_name = $ServerName })
    @($rows | ForEach-Object { Convert-VolumePathToScanPath -Path ([string]$_.volume_mount_point) })
}

function Invoke-BackupRetentionScan {
    Set-AutoHealRequestStatus -Status 'Running' -Message "Scanning backup and log backup files. Files older than $RetentionDays days will be deleted automatically." -DetailsJson $null

    $cutoffUtc = [DateTime]::UtcNow.AddDays(-1 * [Math]::Max(1, $RetentionDays))
    $scanRoots = @(Get-ScanRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($scanRoots.Count -eq 0) {
        throw "No scan target was supplied and no disk volume history was found for $ServerName."
    }

    $foundCount = 0
    $retentionDeletedCount = 0
    $candidateCount = 0
    $failedCount = 0
    $protectedNameSkippedCount = 0
    $windowsFolderSkippedCount = 0

    foreach ($scanRoot in $scanRoots) {
        Write-Host "Scanning $scanRoot for .bak and .trn files..."
        if (-not (Test-Path -LiteralPath $scanRoot)) {
            $failedCount++
            Add-AutoHealFileCandidate -FilePath $scanRoot -Extension $null -SizeMb $null -LastWriteTimeUtc $null -AgeDays $null -IsOlderThanRetention $false -ActionStatus 'Failed' -ErrorMessage "Scan root was not found or was not accessible."
            continue
        }

        $windowsFolderSkippedCount += Get-WholeDriveWindowsDirectoryCount -ScanRoot $scanRoot

        foreach ($file in Get-BackupCandidateFiles -ScanRoot $scanRoot) {
            if (-not (Test-IsBackupFileExtension -Extension $file.Extension)) {
                continue
            }

            if (Test-IsProtectedBackupFileName -File $file) {
                $protectedNameSkippedCount++
                continue
            }

            $foundCount++
            $ageDays = [Math]::Round(([DateTime]::UtcNow - $file.LastWriteTimeUtc).TotalDays, 2)
            $sizeMb = [Math]::Round($file.Length / 1MB, 2)
            $isOlder = $file.LastWriteTimeUtc -lt $cutoffUtc
            $status = 'Candidate'
            $errorMessage = $null

            if ($isOlder) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $status = 'DeletedByRetention'
                    $retentionDeletedCount++
                }
                catch {
                    $status = 'Failed'
                    $errorMessage = $_.Exception.Message
                    $failedCount++
                }
            }
            else {
                $candidateCount++
            }

            Add-AutoHealFileCandidate -FilePath $file.FullName -Extension $file.Extension -SizeMb $sizeMb -LastWriteTimeUtc $file.LastWriteTimeUtc -AgeDays $ageDays -IsOlderThanRetention $isOlder -ActionStatus $status -ErrorMessage $errorMessage
        }
    }

    $details = [ordered]@{
        action = 'BackupRetentionScan'
        serverName = $ServerName
        targetPath = $TargetPath
        scanRoots = $scanRoots
        retentionDays = $RetentionDays
        cutoffUtc = $cutoffUtc.ToString('o')
        foundCount = $foundCount
        retentionDeletedCount = $retentionDeletedCount
        candidateCount = $candidateCount
        failedCount = $failedCount
        protectedNameSkippedCount = $protectedNameSkippedCount
        windowsFolderSkippedCount = $windowsFolderSkippedCount
    } | ConvertTo-Json -Depth 8 -Compress

    $message = "Scan completed. Found $foundCount eligible .bak/.trn files; deleted $retentionDeletedCount older than $RetentionDays days; $candidateCount remain selectable; skipped $protectedNameSkippedCount protected file names and $windowsFolderSkippedCount Windows folder(s); $failedCount failed."
    $status = if ($failedCount -gt 0) { 'CompletedWithWarnings' } else { 'Completed' }
    Set-AutoHealRequestStatus -Status $status -Message $message -DetailsJson $details
}

function Invoke-SelectedFileCleanup {
    Set-AutoHealRequestStatus -Status 'CleanupRunning' -Message 'Deleting selected backup files.' -DetailsJson $null

    $query = @"
SELECT file_path
FROM dbo.AutoHealFileCandidate
WHERE request_id = CONVERT(uniqueidentifier, @request_id)
  AND selected_for_cleanup = 1
  AND action_status IN ('Candidate', 'Failed');
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{ request_id = $RequestId.ToString() })
    $deletedCount = 0
    $failedCount = 0

    foreach ($row in $rows) {
        $filePath = [string]$row.file_path
        $status = 'DeletedSelected'
        $errorMessage = $null

        try {
            $extension = [System.IO.Path]::GetExtension($filePath)
            if ($extension -notin @('.bak', '.trn')) {
                throw "Refusing to delete '$filePath' because it is not a .bak or .trn file."
            }

            $fileInfo = [System.IO.FileInfo]::new($filePath)
            if (Test-IsProtectedBackupFileName -File $fileInfo) {
                throw "Refusing to delete '$filePath' because the file name contains a protected retention keyword."
            }

            if (Test-Path -LiteralPath $filePath) {
                Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop
                $deletedCount++
            }
            else {
                $status = 'Skipped'
                $errorMessage = 'File no longer exists.'
            }
        }
        catch {
            $status = 'Failed'
            $errorMessage = $_.Exception.Message
            $failedCount++
        }

        $updateQuery = @"
UPDATE dbo.AutoHealFileCandidate
SET action_status = @action_status,
    error_message = @error_message
WHERE request_id = CONVERT(uniqueidentifier, @request_id)
  AND file_path = @file_path;
"@

        Invoke-RepositoryQuery -Query $updateQuery -SqlParameter @{
            request_id = $RequestId.ToString()
            file_path = $filePath
            action_status = $status
            error_message = $errorMessage
        } | Out-Null
    }

    $details = [ordered]@{
        action = 'DeleteSelectedBackupFiles'
        selectedCount = $rows.Count
        deletedCount = $deletedCount
        failedCount = $failedCount
    } | ConvertTo-Json -Depth 5 -Compress

    $message = "Selected cleanup completed. Deleted $deletedCount of $($rows.Count) selected files; $failedCount failed."
    $status = if ($failedCount -gt 0) { 'CompletedWithWarnings' } else { 'Completed' }
    Set-AutoHealRequestStatus -Status $status -Message $message -DetailsJson $details
}

function Invoke-LogShrinkAssessment {
    if ([string]::IsNullOrWhiteSpace($DatabaseName)) {
        throw "DatabaseName is required for log shrink assessment."
    }

    Set-AutoHealRequestStatus -Status 'Running' -Message "Assessing whether $ServerName/$DatabaseName log can be safely shrunk." -DetailsJson $null
    Set-SourceConnectionEnvironment

    $assessmentQuery = @"
SELECT
    DB_NAME() AS database_name,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    CAST(ls.total_log_size_in_bytes / 1048576.0 AS DECIMAL(18,2)) AS total_log_size_mb,
    CAST(ls.used_log_space_in_bytes / 1048576.0 AS DECIMAL(18,2)) AS used_log_space_mb,
    CAST(ls.used_log_space_in_percent AS DECIMAL(18,2)) AS used_log_space_percent
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS ls
WHERE d.database_id = DB_ID();
"@

    $transactionQuery = @"
SELECT
    COUNT(DISTINCT st.session_id) AS open_transaction_count,
    MIN(dt.database_transaction_begin_time) AS oldest_transaction_begin_time
FROM sys.dm_tran_database_transactions AS dt
INNER JOIN sys.dm_tran_session_transactions AS st
    ON st.transaction_id = dt.transaction_id
WHERE dt.database_id = DB_ID()
  AND st.session_id <> @@SPID;
"@

    $logFileQuery = @"
SELECT
    name AS logical_file_name,
    CAST(size * 8.0 / 1024.0 AS DECIMAL(18,2)) AS file_size_mb
FROM sys.database_files
WHERE type_desc = 'LOG'
ORDER BY file_id;
"@

    $assessmentRows = @(Invoke-SourceQuery -ServerName $ServerName -Database $DatabaseName -Query $assessmentQuery)
    if ($assessmentRows.Count -eq 0) {
        throw "Could not read log space usage for $ServerName/$DatabaseName."
    }

    $transactionRows = @(Invoke-SourceQuery -ServerName $ServerName -Database $DatabaseName -Query $transactionQuery)
    $logFiles = @(Invoke-SourceQuery -ServerName $ServerName -Database $DatabaseName -Query $logFileQuery)

    $assessment = $assessmentRows[0]
    $transaction = if ($transactionRows.Count -gt 0) { $transactionRows[0] } else { $null }
    $openTransactionCount = if ($transaction) { [int]$transaction.open_transaction_count } else { 0 }
    $usedPercent = [decimal]$assessment.used_log_space_percent
    $totalLogSizeMb = [decimal]$assessment.total_log_size_mb
    $usedLogSizeMb = [decimal]$assessment.used_log_space_mb
    $logReuseWait = [string]$assessment.log_reuse_wait_desc
    $allowedReuseWaits = @('NOTHING', 'CHECKPOINT')
    $minimumTargetSizeMb = Get-AlertThresholdDecimal -AlertType 'LogShrinkAutoHeal' -SettingKey 'MinimumTargetSizeMb' -DefaultValue 256
    $usedLogMultiplier = Get-AlertThresholdDecimal -AlertType 'LogShrinkAutoHeal' -SettingKey 'UsedLogMultiplier' -DefaultValue 2
    $canShrink = $true
    $decisionReasons = New-Object System.Collections.Generic.List[string]

    if ($openTransactionCount -gt 0) {
        $canShrink = $false
        $decisionReasons.Add("Open transaction count is $openTransactionCount.")
    }

    if ($usedPercent -gt 20) {
        $canShrink = $false
        $decisionReasons.Add("Used log space is $usedPercent%, above the 20% auto-shrink safety threshold.")
    }

    if ($totalLogSizeMb -lt 1024) {
        $canShrink = $false
        $decisionReasons.Add("Total log size is below 1024 MB, so shrink is not worth the risk.")
    }

    if ($logReuseWait -notin $allowedReuseWaits) {
        $canShrink = $false
        $decisionReasons.Add("Log reuse wait is $logReuseWait; clear that blocker before shrinking.")
    }

    $shrinkResults = @()
    if ($canShrink) {
        foreach ($logFile in $logFiles) {
            $logicalFileName = [string]$logFile.logical_file_name
            $currentFileSizeMb = [decimal]$logFile.file_size_mb
            $targetMb = [int][Math]::Ceiling([Math]::Max($minimumTargetSizeMb, $usedLogSizeMb * $usedLogMultiplier))

            if ($targetMb -ge $currentFileSizeMb) {
                $decisionReasons.Add("Log file $logicalFileName is already at or below calculated target $targetMb MB.")
                continue
            }

            $shrinkQuery = @"
DECLARE @logical_file_name SYSNAME = @logical_file_name_parameter;
DECLARE @target_mb INT = TRY_CONVERT(INT, @target_mb_parameter);
DBCC SHRINKFILE (@logical_file_name, @target_mb) WITH NO_INFOMSGS;
"@
            Invoke-SourceQuery -ServerName $ServerName -Database $DatabaseName -Query $shrinkQuery -SqlParameter @{
                logical_file_name_parameter = $logicalFileName
                target_mb_parameter = $targetMb
            } | Out-Null

            $postShrinkRows = @(Invoke-SourceQuery -ServerName $ServerName -Database $DatabaseName -Query $logFileQuery)
            $postShrinkFile = $postShrinkRows | Where-Object { [string]::Equals([string]$_.logical_file_name, $logicalFileName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            $postShrinkSizeMb = if ($postShrinkFile) { [decimal]$postShrinkFile.file_size_mb } else { $null }

            $shrinkResults += [ordered]@{
                logicalFileName = $logicalFileName
                previousSizeMb = $currentFileSizeMb
                targetSizeMb = $targetMb
                postShrinkSizeMb = $postShrinkSizeMb
                shrinkLimitedBySqlServer = if ($postShrinkSizeMb -ne $null) { $postShrinkSizeMb -gt $targetMb } else { $null }
            }
        }
    }

    if (-not $canShrink -and $decisionReasons.Count -eq 0) {
        $decisionReasons.Add('Safety checks did not allow shrink.')
    }

    $details = [ordered]@{
        action = 'LogShrinkAssessment'
        serverName = $ServerName
        databaseName = $DatabaseName
        recoveryModel = [string]$assessment.recovery_model_desc
        logReuseWait = $logReuseWait
        totalLogSizeMb = $totalLogSizeMb
        usedLogSpaceMb = $usedLogSizeMb
        usedLogSpacePercent = $usedPercent
        minimumTargetSizeMb = $minimumTargetSizeMb
        usedLogMultiplier = $usedLogMultiplier
        openTransactionCount = $openTransactionCount
        oldestTransactionBeginTime = if ($transaction) { ConvertTo-IsoDateTimeText $transaction.oldest_transaction_begin_time } else { $null }
        canShrink = $canShrink
        decisionReasons = @($decisionReasons)
        shrinkResults = $shrinkResults
    } | ConvertTo-Json -Depth 8 -Compress

    if ($canShrink -and $shrinkResults.Count -gt 0) {
        Set-AutoHealRequestStatus -Status 'Completed' -Message "Log shrink completed for $ServerName/$DatabaseName. Shrunk $($shrinkResults.Count) log file(s)." -DetailsJson $details
    }
    elseif ($canShrink) {
        Set-AutoHealRequestStatus -Status 'Completed' -Message "Log shrink was safe but no file was above the calculated target size." -DetailsJson $details
    }
    else {
        Set-AutoHealRequestStatus -Status 'CompletedWithWarnings' -Message "Log shrink skipped for safety: $($decisionReasons -join ' ')" -DetailsJson $details
    }
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
