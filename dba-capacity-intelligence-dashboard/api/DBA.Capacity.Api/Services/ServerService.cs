using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class ServerService(IDbConnectionFactory connectionFactory) : IServerService
{
    public async Task<IReadOnlyList<ServerInventoryItem>> GetActiveServersAsync(CancellationToken cancellationToken)
    {
        const string sql = """
        SELECT
            server_id AS ServerId,
            server_name AS ServerName,
            environment AS Environment,
            server_type AS ServerType,
            connection_mode AS ConnectionMode
        FROM dbo.ServerInventory
        WHERE is_active = 1
        ORDER BY environment, server_name;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<ServerInventoryItem>(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return rows.AsList();
    }
}
