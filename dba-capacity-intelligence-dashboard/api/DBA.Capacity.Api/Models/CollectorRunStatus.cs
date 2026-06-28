namespace DBA.Capacity.Api.Models;

public sealed record CollectorRunStatus
{
    public bool IsConfigured { get; init; }

    public bool IsRunning { get; init; }

    public int? RunId { get; init; }

    public string? State { get; init; }

    public string? Result { get; init; }

    public string? WebUrl { get; init; }

    public DateTimeOffset? CreatedAt { get; init; }

    public DateTimeOffset? FinishedAt { get; init; }

    public DateTimeOffset? LastCheckedAt { get; init; }

    public string? Message { get; init; }
}
