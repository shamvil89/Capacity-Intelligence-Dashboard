[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

if ($env:DBA_SOURCE_SERVER_TYPE -eq "AzureSQL") {
    Write-Host "Skipping disk space metrics for Azure SQL Database $ServerName. sys.dm_os_volume_stats is not available for Azure SQL Database."
    return
}

$query = @"
SELECT DISTINCT
    @@SERVERNAME AS server_name,
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(vs.total_bytes / 1073741824.0 AS DECIMAL(18,2)) AS total_gb,
    CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(18,2)) AS available_gb
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
ORDER BY vs.volume_mount_point;
"@

Write-Host "Collecting disk space metrics from $ServerName..."
$rows = @(Invoke-SourceQuery -ServerName $ServerName -Database master -Query $query)

foreach ($row in $rows) {
    Invoke-RepositoryProcedure -ProcedureName "dbo.usp_InsertDiskSpaceHistory" -SqlParameter @{
        server_name         = [string]$row.server_name
        volume_mount_point  = [string]$row.volume_mount_point
        logical_volume_name = ConvertTo-NullableValue $row.logical_volume_name
        total_gb            = $row.total_gb
        available_gb        = $row.available_gb
    }
}

Write-Host "Inserted $($rows.Count) disk space rows for $ServerName."
