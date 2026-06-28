using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/dashboard")]
public sealed class DashboardController(IDashboardService dashboardService) : ControllerBase
{
    [HttpGet("summary")]
    [ProducesResponseType(typeof(DashboardSummary), StatusCodes.Status200OK)]
    public async Task<ActionResult<DashboardSummary>> GetSummary(
        [FromQuery] string? riskLevel,
        [FromQuery] string? environment,
        [FromQuery] string? serverName,
        CancellationToken cancellationToken)
    {
        var summary = await dashboardService.GetSummaryAsync(riskLevel, environment, serverName, cancellationToken);
        return Ok(summary);
    }
}
