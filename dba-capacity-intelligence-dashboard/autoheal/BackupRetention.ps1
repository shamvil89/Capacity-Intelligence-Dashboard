[CmdletBinding()]
param()

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
