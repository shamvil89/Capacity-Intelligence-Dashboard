using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface ICollectorRunService
{
    Task<CollectorRunStatus> GetLatestStatusAsync(CancellationToken cancellationToken);

    Task<CollectorRunStatus> QueueRunAsync(CancellationToken cancellationToken);
}
