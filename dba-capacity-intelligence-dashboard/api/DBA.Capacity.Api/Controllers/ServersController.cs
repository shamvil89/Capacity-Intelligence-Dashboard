using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/servers")]
public sealed class ServersController(IServerService serverService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ServerInventoryItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ServerInventoryItem>>> GetActiveServers(CancellationToken cancellationToken)
    {
        var rows = await serverService.GetActiveServersAsync(cancellationToken);
        return Ok(rows);
    }
}
