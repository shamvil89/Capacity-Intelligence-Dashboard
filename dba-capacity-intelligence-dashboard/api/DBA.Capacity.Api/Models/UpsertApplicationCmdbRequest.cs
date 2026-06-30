namespace DBA.Capacity.Api.Models;

public sealed class UpsertApplicationCmdbRequest
{
    public int? ApplicationId { get; init; }
    public int? MappingId { get; init; }
    public string ApplicationName { get; init; } = string.Empty;
    public string? Environment { get; init; }
    public string? ServerName { get; init; }
    public string? DatabaseName { get; init; }
    public bool? IsActive { get; init; }
    public string? ProdOpsTeamEmail { get; init; }
    public string? ApplicationOwnerEmail { get; init; }
    public string? BusinessOwnerEmail { get; init; }
    public string? SupportDlEmail { get; init; }
    public string? EscalationDlEmail { get; init; }
    public string? ServiceNowGroup { get; init; }
    public string? Criticality { get; init; }
    public string? ApplicationUrl { get; init; }
    public string? Notes { get; init; }
}
