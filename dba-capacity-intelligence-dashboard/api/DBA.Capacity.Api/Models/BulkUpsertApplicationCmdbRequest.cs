namespace DBA.Capacity.Api.Models;

public sealed class BulkUpsertApplicationCmdbRequest
{
    public IReadOnlyList<UpsertApplicationCmdbRequest> Entries { get; init; } = [];
}
