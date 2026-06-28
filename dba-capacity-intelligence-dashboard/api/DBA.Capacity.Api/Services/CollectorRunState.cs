using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class CollectorRunState
{
    private readonly object syncRoot = new();
    private CollectorRunStatus? latestStatus;

    public SemaphoreSlim Gate { get; } = new(1, 1);

    public CollectorRunStatus? LatestStatus
    {
        get
        {
            lock (syncRoot)
            {
                return latestStatus;
            }
        }
    }

    public void Store(CollectorRunStatus status)
    {
        lock (syncRoot)
        {
            latestStatus = status;
        }
    }
}
