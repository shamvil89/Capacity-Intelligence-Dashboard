[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

$query = @"
SELECT
    @@SERVERNAME AS server_name,
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        WHEN 'F' THEN 'File'
        WHEN 'G' THEN 'DifferentialFile'
        WHEN 'P' THEN 'Partial'
        WHEN 'Q' THEN 'DifferentialPartial'
        ELSE bs.type
    END AS backup_type,
    CAST(bs.backup_size / 1073741824.0 AS DECIMAL(18,2)) AS backup_size_gb,
    CAST(bs.compressed_backup_size / 1073741824.0 AS DECIMAL(18,2)) AS compressed_backup_size_gb,
    bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
LEFT JOIN msdb.dbo.backupmediafamily AS bmf
    ON bmf.media_set_id = bs.media_set_id
WHERE bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE())
ORDER BY bs.backup_finish_date DESC;
"@

Write-Host "Collecting backup size metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database msdb -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertBackupSizeHistory" -SqlParameter @{
        server_name               = [string]$row.server_name
        database_name             = [string]$row.database_name
        backup_start_date         = ConvertTo-NullableValue $row.backup_start_date
        backup_finish_date        = ConvertTo-NullableValue $row.backup_finish_date
        backup_type               = ConvertTo-NullableValue $row.backup_type
        backup_size_gb            = ConvertTo-NullableValue $row.backup_size_gb
        compressed_backup_size_gb = ConvertTo-NullableValue $row.compressed_backup_size_gb
        physical_device_name      = ConvertTo-NullableValue $row.physical_device_name
    }
}

Write-Host "Inserted $($rows.Count) backup size rows for $ServerName."
