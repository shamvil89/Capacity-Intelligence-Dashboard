namespace DBA.Capacity.Api.Models;

public sealed class CapacityDashboardItem
{
    public string ServerName { get; init; } = string.Empty;
    public string? Environment { get; init; }
    public string DatabaseName { get; init; } = string.Empty;
    public decimal CurrentSizeGb { get; init; }
    public decimal? Growth7DaysGb { get; init; }
    public decimal? Growth30DaysGb { get; init; }
    public decimal? Growth90DaysGb { get; init; }
    public decimal? AverageGrowthPerDayGb { get; init; }
    public decimal? AvailableSpaceGb { get; init; }
    public decimal? EstimatedDaysRemaining { get; init; }
    public string? LimitingVolumeMountPoint { get; init; }
    public decimal? SharedVolumeGrowthPerDayGb { get; init; }
    public string? ForecastMethod { get; init; }
    public string RiskLevel { get; init; } = "Healthy";
    public string? Recommendation { get; init; }
    public DateTime CalculationTime { get; init; }
}
