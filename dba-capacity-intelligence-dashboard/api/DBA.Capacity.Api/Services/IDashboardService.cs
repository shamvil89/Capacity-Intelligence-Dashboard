using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IDashboardService
{
    Task<DashboardSummary> GetSummaryAsync(
        string? riskLevel,
        string? environment,
        string? serverName,
        CancellationToken cancellationToken);
}
