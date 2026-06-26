using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class CapacityService(IDbConnectionFactory connectionFactory) : ICapacityService
{
    public async Task<IReadOnlyList<CapacityDashboardItem>> GetLatestDatabasesAsync(
        string? riskLevel,
        string? serverName,
        string? databaseName,
        CancellationToken cancellationToken)
    {
        var filters = new List<string>();
        var parameters = new DynamicParameters();

        if (!string.IsNullOrWhiteSpace(riskLevel) && !riskLevel.Equals("All", StringComparison.OrdinalIgnoreCase))
        {
            filters.Add("risk_level = @RiskLevel");
            parameters.Add("RiskLevel", riskLevel);
        }

        if (!string.IsNullOrWhiteSpace(serverName))
        {
            filters.Add("server_name = @ServerName");
            parameters.Add("ServerName", serverName);
        }

        if (!string.IsNullOrWhiteSpace(databaseName))
        {
            filters.Add("database_name LIKE @DatabaseName");
            parameters.Add("DatabaseName", $"%{databaseName}%");
        }

        var whereClause = filters.Count > 0 ? $"WHERE {string.Join(" AND ", filters)}" : string.Empty;
        var sql = $"""
        SELECT
            server_name AS ServerName,
            database_name AS DatabaseName,
            current_size_gb AS CurrentSizeGb,
            growth_7d_gb AS Growth7DaysGb,
            growth_30d_gb AS Growth30DaysGb,
            growth_90d_gb AS Growth90DaysGb,
            avg_growth_per_day_30d_gb AS AverageGrowthPerDayGb,
            available_space_gb AS AvailableSpaceGb,
            estimated_days_remaining AS EstimatedDaysRemaining,
            risk_level AS RiskLevel,
            recommendation AS Recommendation,
            calculation_time AS CalculationTime
        FROM dbo.vw_LatestCapacityDashboard
        {whereClause}
        ORDER BY
            CASE risk_level
                WHEN 'Critical' THEN 1
                WHEN 'High' THEN 2
                WHEN 'Medium' THEN 3
                WHEN 'Low' THEN 4
                ELSE 5
            END,
            current_size_gb DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<CapacityDashboardItem>(
            new CommandDefinition(sql, parameters, cancellationToken: cancellationToken));

        return rows.AsList();
    }

    public async Task<IReadOnlyList<DatabaseTrendPoint>> GetDatabaseTrendAsync(
        string serverName,
        string databaseName,
        int days,
        CancellationToken cancellationToken)
    {
        days = Math.Clamp(days, 1, 3650);

        const string sql = """
        SELECT
            collection_time AS CollectionTime,
            server_name AS ServerName,
            database_name AS DatabaseName,
            total_size_gb AS TotalSizeGb,
            data_size_gb AS DataSizeGb,
            log_size_gb AS LogSizeGb
        FROM dbo.vw_DatabaseSizeTrend
        WHERE server_name = @ServerName
          AND database_name = @DatabaseName
          AND collection_time >= DATEADD(DAY, -@Days, SYSUTCDATETIME())
        ORDER BY collection_time;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<DatabaseTrendPoint>(
            new CommandDefinition(
                sql,
                new { ServerName = serverName, DatabaseName = databaseName, Days = days },
                cancellationToken: cancellationToken));

        return rows.AsList();
    }

    public async Task<IReadOnlyList<TopGrowingTableItem>> GetTopGrowingTablesAsync(
        int limit,
        CancellationToken cancellationToken)
    {
        limit = Math.Clamp(limit, 1, 500);

        const string sql = """
        SELECT TOP (@Limit)
            server_name AS ServerName,
            database_name AS DatabaseName,
            schema_name AS SchemaName,
            table_name AS TableName,
            current_size_mb AS CurrentSizeMb,
            growth_30d_mb AS Growth30DaysMb,
            current_row_count AS CurrentRowCount,
            row_growth_30d AS RowGrowth30Days
        FROM dbo.vw_TopGrowingTables
        ORDER BY ISNULL(growth_30d_mb, 0) DESC, ISNULL(current_size_mb, 0) DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<TopGrowingTableItem>(
            new CommandDefinition(sql, new { Limit = limit }, cancellationToken: cancellationToken));

        return rows.AsList();
    }
}
