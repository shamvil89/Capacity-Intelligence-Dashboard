namespace DBA.Capacity.Api.Models;

public sealed class AlertItem
{
    public DateTime AlertTime { get; init; }
    public string ServerName { get; init; } = string.Empty;
    public string? DatabaseName { get; init; }
    public string AlertType { get; init; } = string.Empty;
    public string Severity { get; init; } = string.Empty;
    public string Message { get; init; } = string.Empty;
}
