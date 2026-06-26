namespace DBA.Capacity.Api.Models;

public sealed class ServerInventoryItem
{
    public int ServerId { get; init; }
    public string ServerName { get; init; } = string.Empty;
    public string Environment { get; init; } = string.Empty;
    public string ServerType { get; init; } = string.Empty;
    public string? ConnectionMode { get; init; }
}
