using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/auto-heal")]
public sealed class AutoHealController(IAutoHealService autoHealService) : ControllerBase
{
    [HttpPost("requests")]
    [ProducesResponseType(typeof(AutoHealRequestStatus), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(AutoHealRequestStatus), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<AutoHealRequestStatus>> Queue([FromBody] AutoHealQueueRequest request, CancellationToken cancellationToken)
    {
        var status = await autoHealService.QueueAsync(request, cancellationToken);
        return status.IsConfigured && !string.Equals(status.Status, "InvalidRequest", StringComparison.OrdinalIgnoreCase)
            ? Ok(status)
            : BadRequest(status);
    }

    [HttpGet("requests/{requestId:guid}")]
    [ProducesResponseType(typeof(AutoHealRequestStatus), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AutoHealRequestStatus>> GetStatus(Guid requestId, CancellationToken cancellationToken)
    {
        var status = await autoHealService.GetStatusAsync(requestId, cancellationToken);
        return status is null ? NotFound() : Ok(status);
    }

    [HttpGet("requests/latest")]
    [ProducesResponseType(typeof(AutoHealRequestStatus), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AutoHealRequestStatus>> GetLatestForAlert([FromQuery] long alertId, CancellationToken cancellationToken)
    {
        if (alertId <= 0)
        {
            return NotFound();
        }

        var status = await autoHealService.GetLatestForAlertAsync(alertId, cancellationToken);
        return status is null ? NotFound() : Ok(status);
    }

    [HttpPost("requests/{requestId:guid}/cleanup-files")]
    [ProducesResponseType(typeof(AutoHealRequestStatus), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AutoHealRequestStatus>> QueueSelectedFileCleanup(
        Guid requestId,
        [FromBody] AutoHealCleanupFilesRequest request,
        CancellationToken cancellationToken)
    {
        var status = await autoHealService.QueueSelectedFileCleanupAsync(requestId, request, cancellationToken);
        return status is null ? NotFound() : Ok(status);
    }
}
