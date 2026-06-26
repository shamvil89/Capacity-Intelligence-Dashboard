using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IDashboardService
{
    Task<DashboardSummary> GetSummaryAsync(CancellationToken cancellationToken);
}
