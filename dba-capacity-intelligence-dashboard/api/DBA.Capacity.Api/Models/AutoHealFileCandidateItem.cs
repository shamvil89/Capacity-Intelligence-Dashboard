namespace DBA.Capacity.Api.Models;

public sealed class AutoHealFileCandidateItem
{
    public long CandidateId { get; init; }
    public Guid RequestId { get; init; }
    public DateTime DiscoveredAt { get; init; }
    public string FilePath { get; init; } = string.Empty;
    public string? Extension { get; init; }
    public decimal? SizeMb { get; init; }
    public DateTime? LastWriteTimeUtc { get; init; }
    public decimal? AgeDays { get; init; }
    public bool IsOlderThanRetention { get; init; }
    public bool SelectedForCleanup { get; init; }
    public string ActionStatus { get; init; } = "Candidate";
    public string? ErrorMessage { get; init; }
}
