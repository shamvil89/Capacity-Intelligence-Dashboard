namespace DBA.Capacity.Api.Models;

public sealed record CreateAlertWorkNoteRequest
{
    public string NoteText { get; init; } = "";

    public string? CreatedBy { get; init; }
}
