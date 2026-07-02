using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/alerts")]
public sealed class AlertsController(IAlertService alertService) : ControllerBase
{
    [HttpGet("active")]
    [ProducesResponseType(typeof(IReadOnlyList<AlertItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<AlertItem>>> GetActiveAlerts(CancellationToken cancellationToken)
    {
        var rows = await alertService.GetActiveAlertsAsync(cancellationToken);
        return Ok(rows);
    }

    [HttpGet("history")]
    [ProducesResponseType(typeof(IReadOnlyList<AlertItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<AlertItem>>> GetAlertHistory([FromQuery] int limit = 250, CancellationToken cancellationToken = default)
    {
        var rows = await alertService.GetAlertHistoryAsync(limit, cancellationToken);
        return Ok(rows);
    }

    [HttpGet("{alertId:long}/work-notes")]
    [ProducesResponseType(typeof(IReadOnlyList<AlertWorkNoteItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<AlertWorkNoteItem>>> GetWorkNotes(long alertId, CancellationToken cancellationToken = default)
    {
        var rows = await alertService.GetWorkNotesAsync(alertId, cancellationToken);
        return Ok(rows);
    }

    [HttpPost("{alertId:long}/work-notes")]
    [ProducesResponseType(typeof(AlertWorkNoteItem), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AlertWorkNoteItem>> AddWorkNote(long alertId, [FromBody] CreateAlertWorkNoteRequest request, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.NoteText))
        {
            return BadRequest(new { message = "Work note text is required." });
        }

        var note = await alertService.AddWorkNoteAsync(alertId, request, cancellationToken);
        return note is null
            ? NotFound()
            : CreatedAtAction(nameof(GetWorkNotes), new { alertId }, note);
    }

    [HttpDelete("{alertId:long}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteAlert(long alertId, CancellationToken cancellationToken = default)
    {
        var wasDeleted = await alertService.DeleteAlertAsync(alertId, cancellationToken);
        return wasDeleted ? NoContent() : NotFound();
    }
}
