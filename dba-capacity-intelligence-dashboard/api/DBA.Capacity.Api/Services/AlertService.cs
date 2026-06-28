using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class AlertService(IDbConnectionFactory connectionFactory) : IAlertService
{
    public async Task<IReadOnlyList<AlertItem>> GetActiveAlertsAsync(CancellationToken cancellationToken)
    {
        const string sql = """
        SELECT
            a.alert_id AS AlertId,
            a.alert_time AS AlertTime,
            a.server_name AS ServerName,
            a.database_name AS DatabaseName,
            a.alert_type AS AlertType,
            a.severity AS Severity,
            a.message AS Message,
            COALESCE(a.source_script, source_map.source_script) AS SourceScript,
            COALESCE
            (
                a.details_json,
                (
                    SELECT
                        'LegacyAlert' AS category,
                        a.alert_id AS alertId,
                        a.server_name AS serverName,
                        a.database_name AS databaseName,
                        a.alert_type AS alertType,
                        a.severity,
                        a.message,
                        COALESCE(a.source_script, source_map.source_script) AS sourceScripts,
                        'This alert was created before structured evidence was captured. Run the collector again after deploying the latest database and collector scripts for full metric-specific details.' AS note
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )
            ) AS DetailsJson
        FROM dbo.vw_ActiveAlerts AS a
        CROSS APPLY
        (
            SELECT
                CASE
                    WHEN a.alert_type LIKE 'CollectionFailure:%'
                        THEN CONCAT('Collect-', SUBSTRING(a.alert_type, CHARINDEX(':', a.alert_type) + 1, 100), '.ps1')
                    WHEN a.alert_type = 'CapacityRisk'
                        THEN 'Run-Forecast.ps1; usp_GenerateCapacityForecast.sql; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'LogFileExhaustionRisk'
                        THEN 'Collect-FileSize.ps1; Collect-DiskSpace.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'FullRecoveryNoLogBackup'
                        THEN 'Collect-FileSize.ps1; Collect-BackupSize.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'LongRunningTransaction'
                        THEN 'Collect-LongRunningTransactions.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'BlockingChain'
                        THEN 'Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'ActiveTransactionLogReuseWait'
                        THEN 'Collect-FileSize.ps1; Collect-LongRunningTransactions.ps1; Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'AlwaysOnHealthIssue'
                        THEN 'Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'AlwaysOnLogReuseWait'
                        THEN 'Collect-FileSize.ps1; Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'ReplicationAgentIssue'
                        THEN 'Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'ReplicationLogReuseWait'
                        THEN 'Collect-FileSize.ps1; Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'TempDBUsage'
                        THEN 'Collect-TempDBUsage.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'DiskSpaceLow'
                        THEN 'Collect-DiskSpace.ps1; usp_GenerateAlerts.sql'
                    WHEN a.alert_type = 'BackupGrowth'
                        THEN 'Collect-BackupSize.ps1; usp_GenerateAlerts.sql'
                    ELSE 'usp_GenerateAlerts.sql'
                END AS source_script
        ) AS source_map
        ORDER BY
            CASE a.severity
                WHEN 'Critical' THEN 1
                WHEN 'High' THEN 2
                WHEN 'Medium' THEN 3
                WHEN 'Low' THEN 4
                ELSE 5
            END,
            a.alert_time DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<AlertItem>(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return rows.AsList();
    }
}
