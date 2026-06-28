using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IAlertService
{
    Task<IReadOnlyList<AlertItem>> GetActiveAlertsAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<AlertItem>> GetAlertHistoryAsync(int limit, CancellationToken cancellationToken);
    Task<bool> DeleteAlertAsync(long alertId, CancellationToken cancellationToken);
}
