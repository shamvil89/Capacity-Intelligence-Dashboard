namespace DBA.Capacity.Api.Models;

public sealed class AlertThresholdSettingItem
{
    public int SettingId { get; init; }
    public string AlertType { get; init; } = string.Empty;
    public string SettingKey { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public string? Description { get; init; }
    public string? Unit { get; init; }
    public decimal SettingValueDecimal { get; init; }
    public decimal DefaultValueDecimal { get; init; }
    public decimal? MinimumValueDecimal { get; init; }
    public decimal? MaximumValueDecimal { get; init; }
    public int SortOrder { get; init; }
    public DateTime UpdatedAt { get; init; }
    public string? UpdatedBy { get; init; }
}
