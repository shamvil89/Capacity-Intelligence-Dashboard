using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class AzureDevOpsCollectorRunService(
    HttpClient httpClient,
    IConfiguration configuration,
    CollectorRunState runState,
    ILogger<AzureDevOpsCollectorRunService> logger) : ICollectorRunService
{
    private const string DefaultPipelineName = "DBA Capacity - Collect Metrics";
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private int? resolvedPipelineId;
    private string? resolvedPipelineName;

    public async Task<CollectorRunStatus> GetLatestStatusAsync(CancellationToken cancellationToken)
    {
        var settings = GetSettings();
        if (!settings.IsConfigured)
        {
            return BuildNotConfiguredStatus(settings);
        }

        var latest = runState.LatestStatus;
        if (latest?.RunId is not int runId)
        {
            return new CollectorRunStatus
            {
                IsConfigured = true,
                IsRunning = false,
                State = "idle",
                LastCheckedAt = DateTimeOffset.UtcNow,
                Message = "No collector pipeline run has been triggered from this API instance yet."
            };
        }

        return await GetRunStatusAsync(settings, runId, cancellationToken);
    }

    public async Task<CollectorRunStatus> QueueRunAsync(CancellationToken cancellationToken)
    {
        var settings = GetSettings();
        if (!settings.IsConfigured)
        {
            return BuildNotConfiguredStatus(settings);
        }

        await runState.Gate.WaitAsync(cancellationToken);
        try
        {
            var latest = runState.LatestStatus;
            if (latest?.RunId is int runId)
            {
                var latestStatus = await GetRunStatusAsync(settings, runId, cancellationToken);
                if (latestStatus.IsRunning)
                {
                    return latestStatus with
                    {
                        Message = "Collector pipeline is already running."
                    };
                }
            }

            var pipelineId = await ResolvePipelineIdAsync(settings, cancellationToken);
            if (pipelineId is null)
            {
                return Store(new CollectorRunStatus
                {
                    IsConfigured = true,
                    IsRunning = false,
                    State = "notFound",
                    LastCheckedAt = DateTimeOffset.UtcNow,
                    Message = $"Could not find Azure DevOps pipeline '{settings.PipelineName}'. Configure AzureDevOps:CollectorPipelineId or AZDO_COLLECTOR_PIPELINE_ID."
                });
            }

            var url = BuildUrl(settings, $"_apis/pipelines/{pipelineId}/runs?api-version=7.1");
            using var request = CreateRequest(HttpMethod.Post, url, settings);
            request.Content = new StringContent("{}", Encoding.UTF8, "application/json");

            using var response = await httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return Store(await BuildFailureStatusAsync(response, "Azure DevOps rejected the collector pipeline queue request.", cancellationToken));
            }

            var run = await DeserializeAsync<PipelineRunResponse>(response, cancellationToken);
            if (run?.Id is not int queuedRunId)
            {
                return Store(new CollectorRunStatus
                {
                    IsConfigured = true,
                    IsRunning = false,
                    State = "unknown",
                    LastCheckedAt = DateTimeOffset.UtcNow,
                    Message = "Azure DevOps queued the request but did not return a run id."
                });
            }

            return Store(ToStatus(run, true, "Collector pipeline queued."));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "Collector pipeline queue request failed.");
            return Store(new CollectorRunStatus
            {
                IsConfigured = true,
                IsRunning = false,
                LastCheckedAt = DateTimeOffset.UtcNow,
                Message = $"Collector pipeline request failed: {ex.Message}"
            });
        }
        finally
        {
            runState.Gate.Release();
        }
    }

    private async Task<CollectorRunStatus> GetRunStatusAsync(AzureDevOpsSettings settings, int runId, CancellationToken cancellationToken)
    {
        try
        {
            var pipelineId = await ResolvePipelineIdAsync(settings, cancellationToken);
            if (pipelineId is null)
            {
                return Store(new CollectorRunStatus
                {
                    IsConfigured = true,
                    IsRunning = false,
                    RunId = runId,
                    State = "notFound",
                    LastCheckedAt = DateTimeOffset.UtcNow,
                    Message = $"Could not find Azure DevOps pipeline '{settings.PipelineName}'. Configure AzureDevOps:CollectorPipelineId or AZDO_COLLECTOR_PIPELINE_ID."
                });
            }

            var url = BuildUrl(settings, $"_apis/pipelines/{pipelineId}/runs/{runId}?api-version=7.1");
            using var request = CreateRequest(HttpMethod.Get, url, settings);
            using var response = await httpClient.SendAsync(request, cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                var failure = await BuildFailureStatusAsync(response, "Azure DevOps could not return collector pipeline status.", cancellationToken);
                return Store(failure with
                {
                    RunId = runId,
                    IsRunning = runState.LatestStatus?.IsRunning ?? false,
                    CreatedAt = runState.LatestStatus?.CreatedAt,
                    FinishedAt = runState.LatestStatus?.FinishedAt,
                    WebUrl = runState.LatestStatus?.WebUrl
                });
            }

            var run = await DeserializeAsync<PipelineRunResponse>(response, cancellationToken);
            return Store(ToStatus(run, true, null));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "Collector pipeline status request failed.");
            var latest = runState.LatestStatus;
            return Store((latest ?? new CollectorRunStatus { IsConfigured = true }) with
            {
                LastCheckedAt = DateTimeOffset.UtcNow,
                Message = $"Collector pipeline status check failed: {ex.Message}"
            });
        }
    }

    private async Task<int?> ResolvePipelineIdAsync(AzureDevOpsSettings settings, CancellationToken cancellationToken)
    {
        if (settings.PipelineId is int configuredPipelineId)
        {
            return configuredPipelineId;
        }

        if (resolvedPipelineId is int cachedPipelineId &&
            string.Equals(resolvedPipelineName, settings.PipelineName, StringComparison.OrdinalIgnoreCase))
        {
            return cachedPipelineId;
        }

        var url = BuildUrl(settings, "_apis/pipelines?api-version=7.1");
        using var request = CreateRequest(HttpMethod.Get, url, settings);
        using var response = await httpClient.SendAsync(request, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var body = await ReadBodySnippetAsync(response, cancellationToken);
            logger.LogWarning("Azure DevOps pipeline list failed with {StatusCode}: {Body}", (int)response.StatusCode, body);
            return null;
        }

        var list = await DeserializeAsync<PipelineListResponse>(response, cancellationToken);
        var pipeline = list?.Value.FirstOrDefault(item =>
            string.Equals(item.Name, settings.PipelineName, StringComparison.OrdinalIgnoreCase));

        resolvedPipelineId = pipeline?.Id;
        resolvedPipelineName = pipeline?.Name;
        return pipeline?.Id;
    }

    private CollectorRunStatus ToStatus(PipelineRunResponse? run, bool isConfigured, string? message)
    {
        if (run is null)
        {
            return Store(new CollectorRunStatus
            {
                IsConfigured = isConfigured,
                IsRunning = false,
                State = "unknown",
                LastCheckedAt = DateTimeOffset.UtcNow,
                Message = message ?? "Azure DevOps did not return pipeline run details."
            });
        }

        var isRunning = !string.Equals(run.State, "completed", StringComparison.OrdinalIgnoreCase);
        return new CollectorRunStatus
        {
            IsConfigured = isConfigured,
            IsRunning = isRunning,
            RunId = run.Id,
            State = run.State,
            Result = run.Result,
            WebUrl = run.Links?.Web?.Href ?? run.Url,
            CreatedAt = run.CreatedDate,
            FinishedAt = run.FinishedDate,
            LastCheckedAt = DateTimeOffset.UtcNow,
            Message = message
        };
    }

    private CollectorRunStatus Store(CollectorRunStatus status)
    {
        runState.Store(status);
        return status;
    }

    private HttpRequestMessage CreateRequest(HttpMethod method, string url, AzureDevOpsSettings settings)
    {
        var request = new HttpRequestMessage(method, url);
        var token = Convert.ToBase64String(Encoding.ASCII.GetBytes($":{settings.Pat}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return request;
    }

    private static string BuildUrl(AzureDevOpsSettings settings, string pathAndQuery)
    {
        return $"https://dev.azure.com/{Uri.EscapeDataString(settings.Organization)}/{Uri.EscapeDataString(settings.Project)}/{pathAndQuery}";
    }

    private async Task<T?> DeserializeAsync<T>(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await JsonSerializer.DeserializeAsync<T>(stream, SerializerOptions, cancellationToken);
    }

    private async Task<CollectorRunStatus> BuildFailureStatusAsync(HttpResponseMessage response, string prefix, CancellationToken cancellationToken)
    {
        var body = await ReadBodySnippetAsync(response, cancellationToken);
        var details = string.IsNullOrWhiteSpace(body)
            ? $"{(int)response.StatusCode} {response.ReasonPhrase}"
            : $"{(int)response.StatusCode} {response.ReasonPhrase}: {body}";

        return new CollectorRunStatus
        {
            IsConfigured = true,
            IsRunning = false,
            LastCheckedAt = DateTimeOffset.UtcNow,
            Message = $"{prefix} {details}"
        };
    }

    private static async Task<string> ReadBodySnippetAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (body.Length <= 600)
        {
            return body;
        }

        return body[..600];
    }

    private AzureDevOpsSettings GetSettings()
    {
        var section = configuration.GetSection("AzureDevOps");
        var pipelineIdValue =
            section["CollectorPipelineId"] ??
            configuration["AZDO_COLLECTOR_PIPELINE_ID"];

        int? pipelineId = null;
        if (int.TryParse(pipelineIdValue, out var parsedPipelineId))
        {
            pipelineId = parsedPipelineId;
        }

        return new AzureDevOpsSettings(
            ReadConfig(section, "Organization", "AZDO_ORGANIZATION"),
            ReadConfig(section, "Project", "AZDO_PROJECT"),
            pipelineId,
            ReadConfig(section, "CollectorPipelineName", "AZDO_COLLECTOR_PIPELINE_NAME", DefaultPipelineName),
            ReadConfig(section, "Pat", "AZDO_PAT"));
    }

    private string ReadConfig(IConfiguration section, string sectionKey, string environmentKey, string defaultValue = "")
    {
        var sectionValue = section[sectionKey];
        if (!string.IsNullOrWhiteSpace(sectionValue))
        {
            return sectionValue;
        }

        var environmentValue = configuration[environmentKey];
        return !string.IsNullOrWhiteSpace(environmentValue) && !environmentValue.StartsWith("$(", StringComparison.Ordinal)
            ? environmentValue
            : defaultValue;
    }

    private static CollectorRunStatus BuildNotConfiguredStatus(AzureDevOpsSettings settings)
    {
        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(settings.Organization))
        {
            missing.Add("AzureDevOps:Organization");
        }

        if (string.IsNullOrWhiteSpace(settings.Project))
        {
            missing.Add("AzureDevOps:Project");
        }

        if (string.IsNullOrWhiteSpace(settings.Pat))
        {
            missing.Add("AzureDevOps:Pat");
        }

        if (settings.PipelineId is null && string.IsNullOrWhiteSpace(settings.PipelineName))
        {
            missing.Add("AzureDevOps:CollectorPipelineId or AzureDevOps:CollectorPipelineName");
        }

        return new CollectorRunStatus
        {
            IsConfigured = false,
            IsRunning = false,
            State = "notConfigured",
            LastCheckedAt = DateTimeOffset.UtcNow,
            Message = $"Collector pipeline trigger is not configured. Missing: {string.Join(", ", missing)}."
        };
    }

    private sealed record AzureDevOpsSettings(
        string Organization,
        string Project,
        int? PipelineId,
        string PipelineName,
        string Pat)
    {
        public bool IsConfigured =>
            !string.IsNullOrWhiteSpace(Organization) &&
            !string.IsNullOrWhiteSpace(Project) &&
            !string.IsNullOrWhiteSpace(Pat) &&
            (PipelineId is not null || !string.IsNullOrWhiteSpace(PipelineName));
    }

    private sealed record PipelineListResponse
    {
        public IReadOnlyList<PipelineSummary> Value { get; init; } = [];
    }

    private sealed record PipelineSummary
    {
        public int Id { get; init; }

        public string? Name { get; init; }
    }

    private sealed record PipelineRunResponse
    {
        public int Id { get; init; }

        public string? State { get; init; }

        public string? Result { get; init; }

        public DateTimeOffset? CreatedDate { get; init; }

        public DateTimeOffset? FinishedDate { get; init; }

        [JsonPropertyName("_links")]
        public PipelineRunLinks? Links { get; init; }

        public string? Url { get; init; }
    }

    private sealed record PipelineRunLinks
    {
        public PipelineRunLink? Web { get; init; }
    }

    private sealed record PipelineRunLink
    {
        public string? Href { get; init; }
    }
}
