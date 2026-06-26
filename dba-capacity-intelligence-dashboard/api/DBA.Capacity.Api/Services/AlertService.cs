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
            alert_time AS AlertTime,
            server_name AS ServerName,
            database_name AS DatabaseName,
            alert_type AS AlertType,
            severity AS Severity,
            message AS Message
        FROM dbo.vw_ActiveAlerts
        ORDER BY
            CASE severity
                WHEN 'Critical' THEN 1
                WHEN 'High' THEN 2
                WHEN 'Medium' THEN 3
                WHEN 'Low' THEN 4
                ELSE 5
            END,
            alert_time DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<AlertItem>(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return rows.AsList();
    }
}
