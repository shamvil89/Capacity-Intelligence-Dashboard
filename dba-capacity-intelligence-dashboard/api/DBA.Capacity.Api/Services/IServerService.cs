using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IServerService
{
    Task<IReadOnlyList<ServerInventoryItem>> GetActiveServersAsync(CancellationToken cancellationToken);
}
