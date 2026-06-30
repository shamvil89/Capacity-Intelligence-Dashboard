using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/cmdb")]
public sealed class ApplicationCmdbController(IApplicationCmdbService cmdbService) : ControllerBase
{
    [HttpGet("applications")]
    [ProducesResponseType(typeof(IReadOnlyList<ApplicationCmdbEntryItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ApplicationCmdbEntryItem>>> GetApplications(CancellationToken cancellationToken)
    {
        var rows = await cmdbService.GetEntriesAsync(cancellationToken);
        return Ok(rows);
    }

    [HttpGet("database")]
    [ProducesResponseType(typeof(ApplicationCmdbEntryItem), StatusCodes.Status200OK)]
    public async Task<ActionResult<ApplicationCmdbEntryItem?>> GetDatabaseApplication(
        [FromQuery] string serverName,
        [FromQuery] string databaseName,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(serverName) || string.IsNullOrWhiteSpace(databaseName))
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "serverName and databaseName are required."
            });
        }

        var row = await cmdbService.GetDatabaseEntryAsync(serverName, databaseName, cancellationToken);
        return Ok(row);
    }

    [HttpPut("applications")]
    [ProducesResponseType(typeof(ApplicationCmdbEntryItem), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ApplicationCmdbEntryItem>> UpsertApplication(
        [FromBody] UpsertApplicationCmdbRequest request,
        CancellationToken cancellationToken)
    {
        var validationError = ValidateRequest(request);
        if (validationError is not null)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = validationError
            });
        }

        var row = await cmdbService.UpsertEntryAsync(request, cancellationToken);
        return row is null ? BadRequest() : Ok(row);
    }

    [HttpPost("applications/import")]
    [ProducesResponseType(typeof(IReadOnlyList<ApplicationCmdbEntryItem>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<ApplicationCmdbEntryItem>>> ImportApplications(
        [FromBody] BulkUpsertApplicationCmdbRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Entries.Count == 0)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Import file did not contain any CMDB rows."
            });
        }

        if (request.Entries.Count > 1000)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Import is limited to 1000 rows at a time."
            });
        }

        var invalidRowIndex = request.Entries
            .Select((entry, index) => new { Entry = entry, Index = index + 1, Error = ValidateRequest(entry) })
            .FirstOrDefault(row => row.Error is not null);

        if (invalidRowIndex is not null)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = $"Row {invalidRowIndex.Index}: {invalidRowIndex.Error}"
            });
        }

        var rows = await cmdbService.BulkUpsertEntriesAsync(request.Entries, cancellationToken);
        return Ok(rows);
    }

    [HttpDelete("database-mappings/{mappingId:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteMapping(int mappingId, CancellationToken cancellationToken)
    {
        var wasDeleted = await cmdbService.DeleteMappingAsync(mappingId, cancellationToken);
        return wasDeleted ? NoContent() : NotFound();
    }

    [HttpDelete("applications/{applicationId:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteApplication(int applicationId, CancellationToken cancellationToken)
    {
        var wasDeleted = await cmdbService.DeleteApplicationAsync(applicationId, cancellationToken);
        return wasDeleted ? NoContent() : NotFound();
    }

    private static string? ValidateRequest(UpsertApplicationCmdbRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ApplicationName))
        {
            return "Application name is required.";
        }

        var hasServer = !string.IsNullOrWhiteSpace(request.ServerName);
        var hasDatabase = !string.IsNullOrWhiteSpace(request.DatabaseName);
        if (hasServer != hasDatabase)
        {
            return "Server name and database name must both be provided when mapping an application to a database.";
        }

        return null;
    }
}
