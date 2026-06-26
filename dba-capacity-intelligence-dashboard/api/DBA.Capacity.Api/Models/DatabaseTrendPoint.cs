namespace DBA.Capacity.Api.Models;

public sealed class DatabaseTrendPoint
{
    public DateTime CollectionTime { get; init; }
    public string ServerName { get; init; } = string.Empty;
    public string DatabaseName { get; init; } = string.Empty;
    public decimal TotalSizeGb { get; init; }
    public decimal? DataSizeGb { get; init; }
    public decimal? LogSizeGb { get; init; }
}
