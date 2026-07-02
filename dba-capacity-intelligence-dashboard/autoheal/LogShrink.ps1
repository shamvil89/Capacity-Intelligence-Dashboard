[CmdletBinding()]
param()

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
