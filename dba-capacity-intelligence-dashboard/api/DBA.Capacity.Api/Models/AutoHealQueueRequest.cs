namespace DBA.Capacity.Api.Models;

public sealed class AutoHealQueueRequest
{
    public long? AlertId { get; init; }
    public string? AlertType { get; init; }
    public string ServerName { get; init; } = string.Empty;
    public string? DatabaseName { get; init; }
    public string ActionType { get; init; } = string.Empty;
    public string? TargetPath { get; init; }
    public int? RetentionDays { get; init; }
}
