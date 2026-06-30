using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/collector-run")]
public sealed class CollectorRunController(ICollectorRunService collectorRunService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(CollectorRunStatus), StatusCodes.Status200OK)]
    public async Task<ActionResult<CollectorRunStatus>> GetStatus(CancellationToken cancellationToken)
    {
        var status = await collectorRunService.GetLatestStatusAsync(cancellationToken);
        return Ok(status);
    }

    [HttpPost]
    [ProducesResponseType(typeof(CollectorRunStatus), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(CollectorRunStatus), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<CollectorRunStatus>> QueueRun(CancellationToken cancellationToken)
    {
        var status = await collectorRunService.QueueRunAsync(cancellationToken);
        return status.IsConfigured ? Ok(status) : BadRequest(status);
    }
}
