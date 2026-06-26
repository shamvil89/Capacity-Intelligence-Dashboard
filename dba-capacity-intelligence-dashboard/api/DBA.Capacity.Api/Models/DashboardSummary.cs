namespace DBA.Capacity.Api.Models;

public sealed class DashboardSummary
{
    public int TotalServers { get; init; }
    public int TotalDatabases { get; init; }
    public int CriticalAlerts { get; init; }
    public int HighRiskDatabases { get; init; }
    public string? LargestDatabaseName { get; init; }
    public string? FastestGrowingDatabaseName { get; init; }
}
