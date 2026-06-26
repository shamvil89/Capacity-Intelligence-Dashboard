using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface ICapacityService
{
    Task<IReadOnlyList<CapacityDashboardItem>> GetLatestDatabasesAsync(
        string? riskLevel,
        string? serverName,
        string? databaseName,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<DatabaseTrendPoint>> GetDatabaseTrendAsync(
        string serverName,
        string databaseName,
        int days,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<TopGrowingTableItem>> GetTopGrowingTablesAsync(
        int limit,
        CancellationToken cancellationToken);
}
