[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Initialize-DbaTools

Write-Host "Generating capacity forecasts..."
Invoke-RepositoryQuery -Query "EXEC dbo.usp_GenerateCapacityForecast;" | Out-Null

Write-Host "Generating capacity alerts..."
Invoke-RepositoryQuery -Query "EXEC dbo.usp_GenerateAlerts;" | Out-Null

Write-Host "Forecast and alert generation completed."
