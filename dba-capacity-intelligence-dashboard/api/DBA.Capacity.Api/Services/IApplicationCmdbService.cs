using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface IApplicationCmdbService
{
    Task<IReadOnlyList<ApplicationCmdbEntryItem>> GetEntriesAsync(CancellationToken cancellationToken);
    Task<ApplicationCmdbEntryItem?> GetDatabaseEntryAsync(string serverName, string databaseName, CancellationToken cancellationToken);
    Task<ApplicationCmdbEntryItem?> UpsertEntryAsync(UpsertApplicationCmdbRequest request, CancellationToken cancellationToken);
    Task<IReadOnlyList<ApplicationCmdbEntryItem>> BulkUpsertEntriesAsync(IReadOnlyList<UpsertApplicationCmdbRequest> requests, CancellationToken cancellationToken);
    Task<bool> DeleteMappingAsync(int mappingId, CancellationToken cancellationToken);
    Task<bool> DeleteApplicationAsync(int applicationId, CancellationToken cancellationToken);
}
