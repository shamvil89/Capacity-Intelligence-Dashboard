using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IAutoHealService
{
    Task<AutoHealRequestStatus> QueueAsync(AutoHealQueueRequest request, CancellationToken cancellationToken);

    Task<AutoHealRequestStatus?> GetStatusAsync(Guid requestId, CancellationToken cancellationToken);

    Task<AutoHealRequestStatus?> GetLatestForAlertAsync(long alertId, CancellationToken cancellationToken);

    Task<AutoHealRequestStatus?> QueueSelectedFileCleanupAsync(Guid requestId, AutoHealCleanupFilesRequest request, CancellationToken cancellationToken);
}
