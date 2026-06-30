using System.Data;
using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class ApplicationCmdbService(IDbConnectionFactory connectionFactory) : IApplicationCmdbService
{
    private const string ProjectionSql = """
            app.application_id AS ApplicationId,
            map.mapping_id AS MappingId,
            app.application_name AS ApplicationName,
            map.environment AS Environment,
            map.server_name AS ServerName,
            map.database_name AS DatabaseName,
            map.is_active AS IsActive,
            app.prodops_team_email AS ProdOpsTeamEmail,
            app.application_owner_email AS ApplicationOwnerEmail,
            app.business_owner_email AS BusinessOwnerEmail,
            app.support_dl_email AS SupportDlEmail,
            app.escalation_dl_email AS EscalationDlEmail,
            app.servicenow_group AS ServiceNowGroup,
            app.criticality AS Criticality,
            app.application_url AS ApplicationUrl,
            app.notes AS Notes,
            app.updated_at AS ApplicationUpdatedAt,
            map.updated_at AS MappingUpdatedAt,
            COALESCE(map.updated_by, app.updated_by) AS UpdatedBy
        """;

    public async Task<IReadOnlyList<ApplicationCmdbEntryItem>> GetEntriesAsync(CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT
        {ProjectionSql}
        FROM dbo.ApplicationCmdb AS app
        LEFT JOIN dbo.ApplicationDatabaseMapping AS map
            ON map.application_id = app.application_id
        ORDER BY
            app.application_name,
            CASE WHEN map.mapping_id IS NULL THEN 1 ELSE 0 END,
            map.environment,
            map.server_name,
            map.database_name;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<ApplicationCmdbEntryItem>(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return rows.AsList();
    }

    public async Task<ApplicationCmdbEntryItem?> GetDatabaseEntryAsync(string serverName, string databaseName, CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT TOP (1)
        {ProjectionSql}
        FROM dbo.ApplicationDatabaseMapping AS map
        INNER JOIN dbo.ApplicationCmdb AS app
            ON app.application_id = map.application_id
        WHERE map.database_name = @DatabaseName
          AND map.is_active = 1
          AND
          (
              map.server_name = @ServerName
              OR
              (
                  CHARINDEX(N'.', map.server_name) > 0
                  AND LEFT(map.server_name, CHARINDEX(N'.', map.server_name) - 1) = @ServerName
              )
              OR
              (
                  CHARINDEX(N'.', @ServerName) > 0
                  AND LEFT(@ServerName, CHARINDEX(N'.', @ServerName) - 1) = map.server_name
              )
          )
        ORDER BY CASE WHEN map.server_name = @ServerName THEN 0 ELSE 1 END, map.updated_at DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<ApplicationCmdbEntryItem>(
            new CommandDefinition(
                sql,
                new { ServerName = Clean(serverName), DatabaseName = Clean(databaseName) },
                cancellationToken: cancellationToken));
    }

    public async Task<ApplicationCmdbEntryItem?> UpsertEntryAsync(UpsertApplicationCmdbRequest request, CancellationToken cancellationToken)
    {
        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        using var transaction = connection.BeginTransaction();

        var applicationId = await UpsertApplicationAsync(connection, transaction, request, cancellationToken);
        var mappingId = await UpsertMappingAsync(connection, transaction, applicationId, request, cancellationToken);

        transaction.Commit();

        return mappingId is not null
            ? await GetEntryByMappingIdAsync(mappingId.Value, cancellationToken)
            : await GetEntryByApplicationIdAsync(applicationId, cancellationToken);
    }

    public async Task<IReadOnlyList<ApplicationCmdbEntryItem>> BulkUpsertEntriesAsync(IReadOnlyList<UpsertApplicationCmdbRequest> requests, CancellationToken cancellationToken)
    {
        foreach (var request in requests)
        {
            await UpsertEntryAsync(request, cancellationToken);
        }

        return await GetEntriesAsync(cancellationToken);
    }

    public async Task<bool> DeleteMappingAsync(int mappingId, CancellationToken cancellationToken)
    {
        const string sql = """
        DELETE FROM dbo.ApplicationDatabaseMapping
        WHERE mapping_id = @MappingId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var affectedRows = await connection.ExecuteAsync(
            new CommandDefinition(sql, new { MappingId = mappingId }, cancellationToken: cancellationToken));

        return affectedRows > 0;
    }

    public async Task<bool> DeleteApplicationAsync(int applicationId, CancellationToken cancellationToken)
    {
        const string sql = """
        DELETE FROM dbo.ApplicationCmdb
        WHERE application_id = @ApplicationId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var affectedRows = await connection.ExecuteAsync(
            new CommandDefinition(sql, new { ApplicationId = applicationId }, cancellationToken: cancellationToken));

        return affectedRows > 0;
    }

    private async Task<int> UpsertApplicationAsync(IDbConnection connection, IDbTransaction transaction, UpsertApplicationCmdbRequest request, CancellationToken cancellationToken)
    {
        var applicationName = Clean(request.ApplicationName);
        var applicationId = request.ApplicationId is > 0
            ? await connection.QuerySingleOrDefaultAsync<int?>(
                new CommandDefinition(
                    "SELECT application_id FROM dbo.ApplicationCmdb WHERE application_id = @ApplicationId;",
                    new { request.ApplicationId },
                    transaction,
                    cancellationToken: cancellationToken))
            : null;

        var foundByName = false;
        if (applicationId is null)
        {
            applicationId = await connection.QuerySingleOrDefaultAsync<int?>(
                new CommandDefinition(
                    "SELECT application_id FROM dbo.ApplicationCmdb WHERE application_name = @ApplicationName;",
                    new { ApplicationName = applicationName },
                    transaction,
                    cancellationToken: cancellationToken));
            foundByName = applicationId is not null;
        }

        var parameters = new
        {
            ApplicationId = applicationId,
            ApplicationName = applicationName,
            ProdOpsTeamEmail = Clean(request.ProdOpsTeamEmail),
            ApplicationOwnerEmail = Clean(request.ApplicationOwnerEmail),
            BusinessOwnerEmail = Clean(request.BusinessOwnerEmail),
            SupportDlEmail = Clean(request.SupportDlEmail),
            EscalationDlEmail = Clean(request.EscalationDlEmail),
            ServiceNowGroup = Clean(request.ServiceNowGroup),
            Criticality = Clean(request.Criticality),
            ApplicationUrl = Clean(request.ApplicationUrl),
            Notes = Clean(request.Notes),
            OverwriteAll = request.ApplicationId is > 0 || !foundByName
        };

        if (applicationId is null)
        {
            const string insertSql = """
            INSERT INTO dbo.ApplicationCmdb
            (
                application_name,
                prodops_team_email,
                application_owner_email,
                business_owner_email,
                support_dl_email,
                escalation_dl_email,
                servicenow_group,
                criticality,
                application_url,
                notes,
                created_by,
                updated_by
            )
            VALUES
            (
                @ApplicationName,
                @ProdOpsTeamEmail,
                @ApplicationOwnerEmail,
                @BusinessOwnerEmail,
                @SupportDlEmail,
                @EscalationDlEmail,
                @ServiceNowGroup,
                @Criticality,
                @ApplicationUrl,
                @Notes,
                SUSER_SNAME(),
                SUSER_SNAME()
            );

            SELECT CONVERT(INT, SCOPE_IDENTITY());
            """;

            return await connection.QuerySingleAsync<int>(
                new CommandDefinition(insertSql, parameters, transaction, cancellationToken: cancellationToken));
        }

        const string updateSql = """
        UPDATE dbo.ApplicationCmdb
            SET application_name = @ApplicationName,
                prodops_team_email = CASE WHEN @OverwriteAll = 1 THEN @ProdOpsTeamEmail ELSE COALESCE(@ProdOpsTeamEmail, prodops_team_email) END,
                application_owner_email = CASE WHEN @OverwriteAll = 1 THEN @ApplicationOwnerEmail ELSE COALESCE(@ApplicationOwnerEmail, application_owner_email) END,
                business_owner_email = CASE WHEN @OverwriteAll = 1 THEN @BusinessOwnerEmail ELSE COALESCE(@BusinessOwnerEmail, business_owner_email) END,
                support_dl_email = CASE WHEN @OverwriteAll = 1 THEN @SupportDlEmail ELSE COALESCE(@SupportDlEmail, support_dl_email) END,
                escalation_dl_email = CASE WHEN @OverwriteAll = 1 THEN @EscalationDlEmail ELSE COALESCE(@EscalationDlEmail, escalation_dl_email) END,
                servicenow_group = CASE WHEN @OverwriteAll = 1 THEN @ServiceNowGroup ELSE COALESCE(@ServiceNowGroup, servicenow_group) END,
                criticality = CASE WHEN @OverwriteAll = 1 THEN @Criticality ELSE COALESCE(@Criticality, criticality) END,
                application_url = CASE WHEN @OverwriteAll = 1 THEN @ApplicationUrl ELSE COALESCE(@ApplicationUrl, application_url) END,
                notes = CASE WHEN @OverwriteAll = 1 THEN @Notes ELSE COALESCE(@Notes, notes) END,
                updated_at = SYSUTCDATETIME(),
                updated_by = SUSER_SNAME()
        WHERE application_id = @ApplicationId;
        """;

        await connection.ExecuteAsync(
            new CommandDefinition(updateSql, parameters, transaction, cancellationToken: cancellationToken));

        return applicationId.Value;
    }

    private static async Task<int?> UpsertMappingAsync(IDbConnection connection, IDbTransaction transaction, int applicationId, UpsertApplicationCmdbRequest request, CancellationToken cancellationToken)
    {
        var serverName = Clean(request.ServerName);
        var databaseName = Clean(request.DatabaseName);
        if (serverName is null || databaseName is null)
        {
            return null;
        }

        var mappingId = request.MappingId is > 0
            ? await connection.QuerySingleOrDefaultAsync<int?>(
                new CommandDefinition(
                    "SELECT mapping_id FROM dbo.ApplicationDatabaseMapping WHERE mapping_id = @MappingId;",
                    new { request.MappingId },
                    transaction,
                    cancellationToken: cancellationToken))
            : null;

        mappingId ??= await connection.QuerySingleOrDefaultAsync<int?>(
            new CommandDefinition(
                """
                SELECT mapping_id
                FROM dbo.ApplicationDatabaseMapping
                WHERE server_name = @ServerName
                  AND database_name = @DatabaseName;
                """,
                new { ServerName = serverName, DatabaseName = databaseName },
                transaction,
                cancellationToken: cancellationToken));

        var parameters = new
        {
            MappingId = mappingId,
            ApplicationId = applicationId,
            ServerName = serverName,
            DatabaseName = databaseName,
            Environment = Clean(request.Environment),
            IsActive = request.IsActive ?? true
        };

        if (mappingId is null)
        {
            const string insertSql = """
            INSERT INTO dbo.ApplicationDatabaseMapping
            (
                application_id,
                server_name,
                database_name,
                environment,
                is_active,
                created_by,
                updated_by
            )
            VALUES
            (
                @ApplicationId,
                @ServerName,
                @DatabaseName,
                @Environment,
                @IsActive,
                SUSER_SNAME(),
                SUSER_SNAME()
            );

            SELECT CONVERT(INT, SCOPE_IDENTITY());
            """;

            return await connection.QuerySingleAsync<int>(
                new CommandDefinition(insertSql, parameters, transaction, cancellationToken: cancellationToken));
        }

        const string updateSql = """
        UPDATE dbo.ApplicationDatabaseMapping
            SET application_id = @ApplicationId,
                server_name = @ServerName,
                database_name = @DatabaseName,
                environment = @Environment,
                is_active = @IsActive,
                updated_at = SYSUTCDATETIME(),
                updated_by = SUSER_SNAME()
        WHERE mapping_id = @MappingId;
        """;

        await connection.ExecuteAsync(
            new CommandDefinition(updateSql, parameters, transaction, cancellationToken: cancellationToken));

        return mappingId.Value;
    }

    private async Task<ApplicationCmdbEntryItem?> GetEntryByMappingIdAsync(int mappingId, CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT
        {ProjectionSql}
        FROM dbo.ApplicationDatabaseMapping AS map
        INNER JOIN dbo.ApplicationCmdb AS app
            ON app.application_id = map.application_id
        WHERE map.mapping_id = @MappingId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<ApplicationCmdbEntryItem>(
            new CommandDefinition(sql, new { MappingId = mappingId }, cancellationToken: cancellationToken));
    }

    private async Task<ApplicationCmdbEntryItem?> GetEntryByApplicationIdAsync(int applicationId, CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT TOP (1)
        {ProjectionSql}
        FROM dbo.ApplicationCmdb AS app
        LEFT JOIN dbo.ApplicationDatabaseMapping AS map
            ON map.application_id = app.application_id
        WHERE app.application_id = @ApplicationId
        ORDER BY CASE WHEN map.mapping_id IS NULL THEN 1 ELSE 0 END, map.updated_at DESC;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<ApplicationCmdbEntryItem>(
            new CommandDefinition(sql, new { ApplicationId = applicationId }, cancellationToken: cancellationToken));
    }

    private static string? Clean(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }
}
