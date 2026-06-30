using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class SettingsService(IDbConnectionFactory connectionFactory) : ISettingsService
{
    private const string ProjectionSql = """
            setting_id AS SettingId,
            alert_type AS AlertType,
            setting_key AS SettingKey,
            display_name AS DisplayName,
            description AS Description,
            unit AS Unit,
            setting_value_decimal AS SettingValueDecimal,
            default_value_decimal AS DefaultValueDecimal,
            minimum_value_decimal AS MinimumValueDecimal,
            maximum_value_decimal AS MaximumValueDecimal,
            sort_order AS SortOrder,
            updated_at AS UpdatedAt,
            updated_by AS UpdatedBy
        """;

    public async Task<IReadOnlyList<AlertThresholdSettingItem>> GetAlertThresholdsAsync(CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT
        {ProjectionSql}
        FROM dbo.AlertThresholdSetting
        ORDER BY alert_type, sort_order, setting_key;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<AlertThresholdSettingItem>(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return rows.AsList();
    }

    public async Task<AlertThresholdSettingItem?> GetAlertThresholdAsync(int settingId, CancellationToken cancellationToken)
    {
        var sql = $"""
        SELECT
        {ProjectionSql}
        FROM dbo.AlertThresholdSetting
        WHERE setting_id = @SettingId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<AlertThresholdSettingItem>(
            new CommandDefinition(sql, new { SettingId = settingId }, cancellationToken: cancellationToken));
    }

    public async Task<AlertThresholdSettingItem?> UpdateAlertThresholdAsync(int settingId, decimal settingValueDecimal, CancellationToken cancellationToken)
    {
        const string sql = """
        UPDATE dbo.AlertThresholdSetting
            SET setting_value_decimal = @SettingValueDecimal,
                updated_at = SYSUTCDATETIME(),
                updated_by = SUSER_SNAME()
        WHERE setting_id = @SettingId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var affectedRows = await connection.ExecuteAsync(
            new CommandDefinition(sql, new { SettingId = settingId, SettingValueDecimal = settingValueDecimal }, cancellationToken: cancellationToken));

        return affectedRows == 0
            ? null
            : await GetAlertThresholdAsync(settingId, cancellationToken);
    }

    public async Task<AlertThresholdSettingItem?> ResetAlertThresholdAsync(int settingId, CancellationToken cancellationToken)
    {
        const string sql = """
        UPDATE dbo.AlertThresholdSetting
            SET setting_value_decimal = default_value_decimal,
                updated_at = SYSUTCDATETIME(),
                updated_by = SUSER_SNAME()
        WHERE setting_id = @SettingId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        var affectedRows = await connection.ExecuteAsync(
            new CommandDefinition(sql, new { SettingId = settingId }, cancellationToken: cancellationToken));

        return affectedRows == 0
            ? null
            : await GetAlertThresholdAsync(settingId, cancellationToken);
    }
}
