using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class DashboardService(IDbConnectionFactory connectionFactory) : IDashboardService
{
    public async Task<DashboardSummary> GetSummaryAsync(
        string? riskLevel,
        string? environment,
        string? serverName,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        var serverFilters = new List<string> { "is_active = 1" };
        var capacityFilters = new List<string>();
        var capacityContextFilters = new List<string>();
        var alertFilters = new List<string> { "severity = 'Critical'" };

        if (!string.IsNullOrWhiteSpace(environment) && !environment.Equals("All", StringComparison.OrdinalIgnoreCase))
        {
            serverFilters.Add("environment = @Environment");
            capacityFilters.Add("environment = @Environment");
            capacityContextFilters.Add("environment = @Environment");
            alertFilters.Add("environment = @Environment");
            parameters.Add("Environment", environment);
        }

        if (!string.IsNullOrWhiteSpace(serverName) && !serverName.Equals("All", StringComparison.OrdinalIgnoreCase))
        {
            serverFilters.Add("server_name = @ServerName");
            capacityFilters.Add("server_name = @ServerName");
            capacityContextFilters.Add("server_name = @ServerName");
            alertFilters.Add("server_name = @ServerName");
            parameters.Add("ServerName", serverName);
        }

        if (!string.IsNullOrWhiteSpace(riskLevel) && !riskLevel.Equals("All", StringComparison.OrdinalIgnoreCase))
        {
            capacityFilters.Add("risk_level = @RiskLevel");
            parameters.Add("RiskLevel", riskLevel);
        }

        var serverWhereClause = $"WHERE {string.Join(" AND ", serverFilters)}";
        var capacityWhereClause = capacityFilters.Count > 0 ? $"WHERE {string.Join(" AND ", capacityFilters)}" : string.Empty;
        var capacityContextWhereClause = capacityContextFilters.Count > 0 ? $"WHERE {string.Join(" AND ", capacityContextFilters)}" : string.Empty;
        var alertWhereClause = $"WHERE {string.Join(" AND ", alertFilters)}";

        var sql = $"""
        SELECT COUNT(1)
        FROM dbo.ServerInventory
        {serverWhereClause};

        SELECT COUNT(1)
        FROM dbo.vw_LatestCapacityDashboard
        {capacityWhereClause};

        SELECT COUNT(1)
        FROM dbo.vw_ActiveAlerts
        {alertWhereClause};

        SELECT COUNT(1)
        FROM dbo.vw_LatestCapacityDashboard
        {capacityContextWhereClause}
        {(capacityContextWhereClause.Length > 0 ? "AND" : "WHERE")} risk_level = 'High';

        SELECT TOP (1) CONCAT(server_name, '/', database_name)
        FROM dbo.vw_LatestCapacityDashboard
        {capacityWhereClause}
        ORDER BY current_size_gb DESC;

        SELECT TOP (1) CONCAT(server_name, '/', database_name)
        FROM dbo.vw_LatestCapacityDashboard
        {capacityWhereClause}
        ORDER BY ISNULL(growth_30d_gb, 0) DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        using var grid = await connection.QueryMultipleAsync(new CommandDefinition(sql, parameters, cancellationToken: cancellationToken));

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
