using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/capacity")]
public sealed class CapacityController(ICapacityService capacityService) : ControllerBase
{
    private static readonly HashSet<string> ValidRiskLevels = new(StringComparer.OrdinalIgnoreCase)
    {
        "All",
        "Healthy",
        "Low",
        "Medium",
        "High",
        "Critical"
    };

    [HttpGet("databases")]
    [ProducesResponseType(typeof(IReadOnlyList<CapacityDashboardItem>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<CapacityDashboardItem>>> GetDatabases(
        [FromQuery] string? riskLevel,
        [FromQuery] string? serverName,
        [FromQuery] string? databaseName,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(riskLevel) && !ValidRiskLevels.Contains(riskLevel))
        {
            return BadRequest(new { message = "riskLevel must be one of All, Healthy, Low, Medium, High, Critical." });
        }

        var rows = await capacityService.GetLatestDatabasesAsync(riskLevel, serverName, databaseName, cancellationToken);
        return Ok(rows);
    }

    [HttpGet("databases/{serverName}/{databaseName}/trend")]
    [ProducesResponseType(typeof(IReadOnlyList<DatabaseTrendPoint>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<DatabaseTrendPoint>>> GetDatabaseTrend(
        string serverName,
        string databaseName,
        [FromQuery] int days = 90,
        CancellationToken cancellationToken = default)
    {
        if (days <= 0)
        {
            return BadRequest(new { message = "days must be greater than zero." });
        }

        var rows = await capacityService.GetDatabaseTrendAsync(serverName, databaseName, days, cancellationToken);
        return Ok(rows);
    }

    [HttpGet("top-growing-tables")]
    [ProducesResponseType(typeof(IReadOnlyList<TopGrowingTableItem>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<TopGrowingTableItem>>> GetTopGrowingTables(
        [FromQuery] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        if (limit <= 0)
        {
            return BadRequest(new { message = "limit must be greater than zero." });
        }

        var rows = await capacityService.GetTopGrowingTablesAsync(limit, cancellationToken);
        return Ok(rows);
    }
}
