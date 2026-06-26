namespace DBA.Capacity.Api.Models;

public sealed class TopGrowingTableItem
{
    public string ServerName { get; init; } = string.Empty;
    public string DatabaseName { get; init; } = string.Empty;
    public string SchemaName { get; init; } = string.Empty;
    public string TableName { get; init; } = string.Empty;
    public decimal? CurrentSizeMb { get; init; }
    public decimal? Growth30DaysMb { get; init; }
    public long? CurrentRowCount { get; init; }
    public long? RowGrowth30Days { get; init; }
}
