namespace DBA.Capacity.Api.Models;

public sealed record AlertWorkNoteItem
{
    public long NoteId { get; init; }

    public long AlertId { get; init; }

    public Guid? RequestId { get; init; }

    public DateTime NoteTime { get; init; }

    public string NoteType { get; init; } = "";

    public string NoteSource { get; init; } = "";

    public string CreatedBy { get; init; } = "";

    public string NoteText { get; init; } = "";

    public string? DetailsJson { get; init; }
}
