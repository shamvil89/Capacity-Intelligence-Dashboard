namespace DBA.Capacity.Api.Models;

public sealed record AutoHealRequestStatus
{
    public Guid RequestId { get; init; }
    public DateTime RequestedAt { get; init; }
    public DateTime? CompletedAt { get; init; }
    public long? AlertId { get; init; }
    public string? AlertType { get; init; }
    public string ServerName { get; init; } = string.Empty;
    public string? DatabaseName { get; init; }
    public string ActionType { get; init; } = string.Empty;
    public string? TargetPath { get; init; }
    public int? RetentionDays { get; init; }
    public string Status { get; init; } = "Queued";
    public int? PipelineRunId { get; init; }
    public string? PipelineWebUrl { get; init; }
    public string? Message { get; init; }
    public string? DetailsJson { get; init; }
    public bool IsConfigured { get; init; } = true;
    public bool IsRunning { get; init; }
    public IReadOnlyList<AutoHealFileCandidateItem> FileCandidates { get; init; } = [];
}
