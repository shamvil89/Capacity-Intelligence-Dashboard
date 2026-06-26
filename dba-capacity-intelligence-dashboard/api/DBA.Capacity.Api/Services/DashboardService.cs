using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class DashboardService(IDbConnectionFactory connectionFactory) : IDashboardService
{
    public async Task<DashboardSummary> GetSummaryAsync(CancellationToken cancellationToken)
    {
        const string sql = """
        SELECT COUNT(1)
        FROM dbo.ServerInventory
        WHERE is_active = 1;

        SELECT COUNT(1)
        FROM dbo.vw_LatestCapacityDashboard;

        SELECT COUNT(1)
        FROM dbo.vw_ActiveAlerts
        WHERE severity = 'Critical';

        SELECT COUNT(1)
        FROM dbo.vw_LatestCapacityDashboard
        WHERE risk_level = 'High';

        SELECT TOP (1) CONCAT(server_name, '/', database_name)
        FROM dbo.vw_LatestCapacityDashboard
        ORDER BY current_size_gb DESC;

        SELECT TOP (1) CONCAT(server_name, '/', database_name)
        FROM dbo.vw_LatestCapacityDashboard
        ORDER BY ISNULL(growth_30d_gb, 0) DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        using var grid = await connection.QueryMultipleAsync(new CommandDefinition(sql, cancellationToken: cancellationToken));

        return new DashboardSummary
        {
            TotalServers = await grid.ReadSingleAsync<int>(),
            TotalDatabases = await grid.ReadSingleAsync<int>(),
            CriticalAlerts = await grid.ReadSingleAsync<int>(),
            HighRiskDatabases = await grid.ReadSingleAsync<int>(),
            LargestDatabaseName = await grid.ReadFirstOrDefaultAsync<string>(),
            FastestGrowingDatabaseName = await grid.ReadFirstOrDefaultAsync<string>()
        };
    }
}
