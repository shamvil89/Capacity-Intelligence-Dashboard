namespace DBA.Capacity.Api.Models;

public sealed class AutoHealCleanupFilesRequest
{
    public IReadOnlyList<string> FilePaths { get; init; } = [];
}
