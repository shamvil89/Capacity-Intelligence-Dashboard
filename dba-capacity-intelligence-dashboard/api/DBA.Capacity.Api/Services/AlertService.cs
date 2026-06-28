using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class AlertService(IDbConnectionFactory connectionFactory) : IAlertService
{
    private const string SourceMapSql = """
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
        """;

    private const string AlertProjectionSql = """
            a.alert_id AS AlertId,
            a.alert_time AS AlertTime,
            a.server_name AS ServerName,
            a.environment AS Environment,
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
                        a.environment AS environment,
                        a.database_name AS databaseName,
                        a.alert_type AS alertType,
                        a.severity,
                        a.message,
                        COALESCE(a.source_script, source_map.source_script) AS sourceScripts,
                        'This alert was created before structured evidence was captured. Run the collector again after deploying the latest database and collector scripts for full metric-specific details.' AS note
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )
            ) AS DetailsJson,
            a.is_resolved AS IsResolved,
            a.resolved_at AS ResolvedAt
        """;

    public async Task<IReadOnlyList<AlertItem>> GetActiveAlertsAsync(CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT
        {AlertProjectionSql}
        FROM dbo.vw_ActiveAlerts AS a
        {SourceMapSql}
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

    public async Task<IReadOnlyList<AlertItem>> GetAlertHistoryAsync(int limit, CancellationToken cancellationToken)
    {
        var safeLimit = Math.Clamp(limit, 1, 1000);
        var sql = $"""
        SELECT TOP (@Limit)
        {AlertProjectionSql}
        FROM
        (
            SELECT
                ah.alert_id,
                ah.alert_time,
                ah.alert_key,
                ah.server_name,
                si.environment,
                ah.database_name,
                ah.alert_type,
                ah.severity,
                ah.message,
                ah.source_script,
                ah.details_json,
                ah.is_resolved,
                ah.resolved_at
            FROM dbo.AlertHistory AS ah
            OUTER APPLY
            (
                SELECT TOP (1)
                    si.environment
                FROM dbo.ServerInventory AS si
                WHERE si.server_name = ah.server_name
                   OR
                   (
                       CHARINDEX(N'.', si.server_name) > 0
                       AND LEFT(si.server_name, CHARINDEX(N'.', si.server_name) - 1) = ah.server_name
                   )
                ORDER BY CASE WHEN si.server_name = ah.server_name THEN 0 ELSE 1 END
            ) AS si
            WHERE ah.is_resolved = 1
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.AlertHistory AS active_alert
                  WHERE active_alert.is_resolved = 0
                    AND active_alert.server_name = ah.server_name
                    AND ISNULL(active_alert.database_name, N'') = ISNULL(ah.database_name, N'')
                    AND active_alert.alert_type = ah.alert_type
                    AND
                    (
                        (
                            active_alert.alert_key IS NOT NULL
                            AND ah.alert_key IS NOT NULL
                            AND active_alert.alert_key = ah.alert_key
                        )
                        OR active_alert.alert_key IS NULL
                        OR ah.alert_key IS NULL
                    )
              )
        ) AS a
        {SourceMapSql}
        ORDER BY a.alert_time DESC, a.alert_id DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<AlertItem>(
            new CommandDefinition(sql, new { Limit = safeLimit }, cancellationToken: cancellationToken));

        return rows.AsList();
    }

    public async Task<bool> DeleteAlertAsync(long alertId, CancellationToken cancellationToken)
    {
        const string sql = """
        DELETE FROM dbo.AlertHistory
        WHERE alert_id = @AlertId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var affectedRows = await connection.ExecuteAsync(
            new CommandDefinition(sql, new { AlertId = alertId }, cancellationToken: cancellationToken));

        return affectedRows > 0;
    }
}
