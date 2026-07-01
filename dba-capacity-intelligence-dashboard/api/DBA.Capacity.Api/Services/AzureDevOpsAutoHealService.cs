using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Dapper;
using DBA.Capacity.Api.Data;
using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public sealed class AzureDevOpsAutoHealService(
    IDbConnectionFactory connectionFactory,
    HttpClient httpClient,
    IConfiguration configuration,
    ILogger<AzureDevOpsAutoHealService> logger) : IAutoHealService
{
    private const string DefaultPipelineName = "DBA Capacity - Auto Heal";
    private const string EmptyDatabaseTemplateValue = "__NONE__";
    private const string AutoBackupPathTemplateValue = "__AUTO__";
    private static readonly HashSet<string> RunningStatuses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Queued",
        "Running",
        "CleanupQueued",
        "CleanupRunning"
    };
    private static readonly HashSet<string> LogShrinkAlertTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "UnusuallyLargeLogFile",
        "LogFileExhaustionRisk",
        "LogFileGrowthSpike"
    };
    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private int? resolvedPipelineId;
    private string? resolvedPipelineName;

    public async Task<AutoHealRequestStatus> QueueAsync(AutoHealQueueRequest request, CancellationToken cancellationToken)
    {
        var actionType = NormalizeActionType(request.ActionType);
        if (actionType is null || string.Equals(actionType, "DeleteSelectedBackupFiles", StringComparison.OrdinalIgnoreCase))
        {
            return BuildImmediateFailure(request, "Unsupported auto-heal action. Use BackupRetentionScan or LogShrinkAssessment.");
        }

        var eligibilityError = ValidateActionEligibility(actionType, request);
        if (eligibilityError is not null)
        {
            return BuildImmediateFailure(request, eligibilityError);
        }

        var serverName = Clean(request.ServerName);
        if (serverName is null)
        {
            return BuildImmediateFailure(request, "Server name is required.");
        }

        var requestId = Guid.NewGuid();
        var retentionDays = Math.Clamp(request.RetentionDays ?? 90, 1, 3650);

        await InsertRequestAsync(requestId, request, actionType, serverName, retentionDays, cancellationToken);

        var queuedStatus = await QueuePipelineForRequestAsync(
            requestId,
            actionType,
            serverName,
            Clean(request.DatabaseName),
            Clean(request.TargetPath),
            retentionDays,
            "Running",
            cancellationToken);

        return queuedStatus ?? await QueryStatusAsync(requestId, false, cancellationToken) ?? BuildMissingStatus(requestId);
    }

    public async Task<AutoHealRequestStatus?> GetStatusAsync(Guid requestId, CancellationToken cancellationToken)
    {
        return await QueryStatusAsync(requestId, true, cancellationToken);
    }

    public async Task<AutoHealRequestStatus?> QueueSelectedFileCleanupAsync(Guid requestId, AutoHealCleanupFilesRequest request, CancellationToken cancellationToken)
    {
        var current = await QueryStatusAsync(requestId, true, cancellationToken);
        if (current is null)
        {
            return null;
        }

        var selectedPaths = request.FilePaths
            .Select(Clean)
            .Where(value => value is not null)
            .Select(value => value!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (selectedPaths.Length == 0)
        {
            await UpdateRequestMessageAsync(requestId, "Select one or more files before cleanup.", cancellationToken);
            return await QueryStatusAsync(requestId, false, cancellationToken);
        }

        using (var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken))
        {
            await connection.ExecuteAsync(
                new CommandDefinition(
                    """
                    UPDATE dbo.AutoHealFileCandidate
                    SET selected_for_cleanup = 0
                    WHERE request_id = @RequestId
                      AND action_status IN ('Candidate', 'Failed');
                    """,
                    new { RequestId = requestId },
                    cancellationToken: cancellationToken));

            foreach (var filePath in selectedPaths)
            {
                await connection.ExecuteAsync(
                    new CommandDefinition(
                        """
                        UPDATE dbo.AutoHealFileCandidate
                        SET selected_for_cleanup = 1,
                            action_status = CASE WHEN action_status = 'Failed' THEN 'Candidate' ELSE action_status END,
                            error_message = NULL
                        WHERE request_id = @RequestId
                          AND file_path = @FilePath
                          AND action_status IN ('Candidate', 'Failed');
                        """,
                        new { RequestId = requestId, FilePath = filePath },
                        cancellationToken: cancellationToken));
            }
        }

        var queuedStatus = await QueuePipelineForRequestAsync(
            requestId,
            "DeleteSelectedBackupFiles",
            current.ServerName,
            current.DatabaseName,
            current.TargetPath,
            current.RetentionDays ?? 90,
            "CleanupRunning",
            cancellationToken);

        return queuedStatus ?? await QueryStatusAsync(requestId, false, cancellationToken);
    }

    private async Task InsertRequestAsync(Guid requestId, AutoHealQueueRequest request, string actionType, string serverName, int retentionDays, CancellationToken cancellationToken)
    {
        const string sql = """
        INSERT INTO dbo.AutoHealRequest
        (
            request_id,
            alert_id,
            alert_type,
            server_name,
            database_name,
            action_type,
            target_path,
            retention_days,
            status,
            message,
            details_json
        )
        VALUES
        (
            @RequestId,
            @AlertId,
            @AlertType,
            @ServerName,
            @DatabaseName,
            @ActionType,
            @TargetPath,
            @RetentionDays,
            'Queued',
            'Auto-heal request queued from dashboard.',
            @DetailsJson
        );
        """;

        var details = JsonSerializer.Serialize(new
        {
            request.AlertId,
            request.AlertType,
            ServerName = serverName,
            DatabaseName = Clean(request.DatabaseName),
            ActionType = actionType,
            TargetPath = Clean(request.TargetPath),
            RetentionDays = retentionDays,
            RequestedFrom = "Dashboard"
        }, SerializerOptions);

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(
            new CommandDefinition(
                sql,
                new
                {
                    RequestId = requestId,
                    request.AlertId,
                    AlertType = Clean(request.AlertType),
                    ServerName = serverName,
                    DatabaseName = Clean(request.DatabaseName),
                    ActionType = actionType,
                    TargetPath = Clean(request.TargetPath),
                    RetentionDays = retentionDays,
                    DetailsJson = details
                },
                cancellationToken: cancellationToken));
    }

    private async Task<AutoHealRequestStatus?> QueuePipelineForRequestAsync(
        Guid requestId,
        string actionType,
        string serverName,
        string? databaseName,
        string? targetPath,
        int retentionDays,
        string runningStatus,
        CancellationToken cancellationToken)
    {
        var settings = GetSettings();
        if (!settings.IsConfigured)
        {
            await UpdateRequestAfterQueueAsync(requestId, "NotConfigured", null, null, BuildNotConfiguredMessage(settings), cancellationToken);
            var notConfigured = await QueryStatusAsync(requestId, false, cancellationToken);
            return notConfigured is null ? null : notConfigured with { IsConfigured = false };
        }

        var pipelineId = await ResolvePipelineIdAsync(settings, cancellationToken);
        if (pipelineId is null)
        {
            await UpdateRequestAfterQueueAsync(
                requestId,
                "NotFound",
                null,
                null,
                $"Could not find Azure DevOps pipeline '{settings.PipelineName}'. Configure AzureDevOps:AutoHealPipelineId or AZDO_AUTOHEAL_PIPELINE_ID.",
                cancellationToken);
            return await QueryStatusAsync(requestId, false, cancellationToken);
        }

        try
        {
            var url = BuildUrl(settings, $"_apis/pipelines/{pipelineId}/runs?api-version=7.1");
            using var httpRequest = CreateRequest(HttpMethod.Post, url, settings);
            var templateParameters = new Dictionary<string, string>
            {
                ["action"] = actionType,
                ["requestId"] = requestId.ToString("D"),
                ["serverName"] = serverName,
                ["databaseName"] = string.IsNullOrWhiteSpace(databaseName) ? EmptyDatabaseTemplateValue : databaseName,
                ["backupScanPath"] = string.IsNullOrWhiteSpace(targetPath) ? AutoBackupPathTemplateValue : targetPath,
                ["retentionDays"] = retentionDays.ToString()
            }
            .Where(parameter => !string.IsNullOrWhiteSpace(parameter.Value))
            .ToDictionary(parameter => parameter.Key, parameter => parameter.Value);

            var body = new
            {
                templateParameters
            };
            httpRequest.Content = new StringContent(JsonSerializer.Serialize(body, SerializerOptions), Encoding.UTF8, "application/json");

            using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                await UpdateRequestAfterQueueAsync(
                    requestId,
                    "QueueFailed",
                    null,
                    null,
                    await BuildFailureMessageAsync(response, "Azure DevOps rejected the auto-heal pipeline queue request.", cancellationToken),
                    cancellationToken);
                return await QueryStatusAsync(requestId, false, cancellationToken);
            }

            var run = await DeserializeAsync<PipelineRunResponse>(response, cancellationToken);
            await UpdateRequestAfterQueueAsync(
                requestId,
                runningStatus,
                run?.Id,
                run?.Links?.Web?.Href ?? run?.Url,
                $"Auto-heal pipeline queued for {actionType}.",
                cancellationToken);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "Auto-heal pipeline queue request failed.");
            await UpdateRequestAfterQueueAsync(
                requestId,
                "QueueFailed",
                null,
                null,
                $"Auto-heal pipeline request failed: {ex.Message}",
                cancellationToken);
        }

        return await QueryStatusAsync(requestId, false, cancellationToken);
    }

    private async Task<AutoHealRequestStatus?> QueryStatusAsync(Guid requestId, bool refreshPipelineStatus, CancellationToken cancellationToken)
    {
        const string requestSql = """
        SELECT
            request_id AS RequestId,
            requested_at AS RequestedAt,
            completed_at AS CompletedAt,
            alert_id AS AlertId,
            alert_type AS AlertType,
            server_name AS ServerName,
            database_name AS DatabaseName,
            action_type AS ActionType,
            target_path AS TargetPath,
            retention_days AS RetentionDays,
            status AS Status,
            pipeline_run_id AS PipelineRunId,
            pipeline_web_url AS PipelineWebUrl,
            message AS Message,
            details_json AS DetailsJson
        FROM dbo.AutoHealRequest
        WHERE request_id = @RequestId;
        """;

        const string candidatesSql = """
        SELECT
            candidate_id AS CandidateId,
            request_id AS RequestId,
            discovered_at AS DiscoveredAt,
            file_path AS FilePath,
            extension AS Extension,
            size_mb AS SizeMb,
            last_write_time_utc AS LastWriteTimeUtc,
            age_days AS AgeDays,
            is_older_than_retention AS IsOlderThanRetention,
            selected_for_cleanup AS SelectedForCleanup,
            action_status AS ActionStatus,
            error_message AS ErrorMessage
        FROM dbo.AutoHealFileCandidate
        WHERE request_id = @RequestId
        ORDER BY
            CASE action_status
                WHEN 'Failed' THEN 0
                WHEN 'Candidate' THEN 1
                WHEN 'DeletedByRetention' THEN 2
                WHEN 'DeletedSelected' THEN 3
                ELSE 4
            END,
            size_mb DESC,
            file_path;
        """;

        AutoHealRequestStatus? status;
        IReadOnlyList<AutoHealFileCandidateItem> candidates;

        using (var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken))
        {
            status = await connection.QuerySingleOrDefaultAsync<AutoHealRequestStatus>(
                new CommandDefinition(requestSql, new { RequestId = requestId }, cancellationToken: cancellationToken));
            if (status is null)
            {
                return null;
            }

            var rows = await connection.QueryAsync<AutoHealFileCandidateItem>(
                new CommandDefinition(candidatesSql, new { RequestId = requestId }, cancellationToken: cancellationToken));
            candidates = rows.AsList();
        }

        if (refreshPipelineStatus && status.PipelineRunId is int runId && RunningStatuses.Contains(status.Status))
        {
            await RefreshPipelineStatusAsync(status, runId, cancellationToken);
            return await QueryStatusAsync(requestId, false, cancellationToken);
        }

        return status with
        {
            IsRunning = RunningStatuses.Contains(status.Status),
            IsConfigured = !string.Equals(status.Status, "NotConfigured", StringComparison.OrdinalIgnoreCase),
            FileCandidates = candidates
        };
    }

    private async Task RefreshPipelineStatusAsync(AutoHealRequestStatus status, int runId, CancellationToken cancellationToken)
    {
        var settings = GetSettings();
        if (!settings.IsConfigured)
        {
            return;
        }

        try
        {
            var pipelineId = await ResolvePipelineIdAsync(settings, cancellationToken);
            if (pipelineId is null)
            {
                return;
            }

            var url = BuildUrl(settings, $"_apis/pipelines/{pipelineId}/runs/{runId}?api-version=7.1");
            using var request = CreateRequest(HttpMethod.Get, url, settings);
            using var response = await httpClient.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return;
            }

            var run = await DeserializeAsync<PipelineRunResponse>(response, cancellationToken);
            if (run is null || !string.Equals(run.State, "completed", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var currentStatus = string.Equals(run.Result, "succeeded", StringComparison.OrdinalIgnoreCase)
                ? "Completed"
                : "Failed";
            var message = string.Equals(currentStatus, "Completed", StringComparison.OrdinalIgnoreCase)
                ? status.Message
                : $"Auto-heal pipeline completed with result {run?.Result ?? "unknown"}.";

            using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
            await connection.ExecuteAsync(
                new CommandDefinition(
                    """
                    UPDATE dbo.AutoHealRequest
                    SET status = CASE
                            WHEN status IN ('Queued', 'Running', 'CleanupQueued', 'CleanupRunning') THEN @Status
                            ELSE status
                        END,
                        completed_at = CASE
                            WHEN status IN ('Queued', 'Running', 'CleanupQueued', 'CleanupRunning') THEN COALESCE(@CompletedAt, SYSUTCDATETIME())
                            ELSE completed_at
                        END,
                        message = CASE
                            WHEN status IN ('Queued', 'Running', 'CleanupQueued', 'CleanupRunning') THEN @Message
                            ELSE message
                        END
                    WHERE request_id = @RequestId;
                    """,
                    new
                    {
                        status.RequestId,
                        Status = currentStatus,
                        CompletedAt = run?.FinishedDate?.UtcDateTime,
                        Message = message
                    },
                    cancellationToken: cancellationToken));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "Auto-heal pipeline status refresh failed for {RequestId}.", status.RequestId);
        }
    }

    private async Task UpdateRequestAfterQueueAsync(Guid requestId, string status, int? runId, string? webUrl, string message, CancellationToken cancellationToken)
    {
        const string sql = """
        UPDATE dbo.AutoHealRequest
        SET status = @Status,
            pipeline_run_id = COALESCE(@PipelineRunId, pipeline_run_id),
            pipeline_web_url = COALESCE(@PipelineWebUrl, pipeline_web_url),
            message = @Message,
            completed_at = CASE WHEN @Status IN ('QueueFailed', 'NotConfigured', 'NotFound') THEN SYSUTCDATETIME() ELSE completed_at END
        WHERE request_id = @RequestId;
        """;

        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(
            new CommandDefinition(
                sql,
                new
                {
                    RequestId = requestId,
                    Status = status,
                    PipelineRunId = runId,
                    PipelineWebUrl = webUrl,
                    Message = message
                },
                cancellationToken: cancellationToken));
    }

    private async Task UpdateRequestMessageAsync(Guid requestId, string message, CancellationToken cancellationToken)
    {
        using var connection = await connectionFactory.CreateOpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(
            new CommandDefinition(
                "UPDATE dbo.AutoHealRequest SET message = @Message WHERE request_id = @RequestId;",
                new { RequestId = requestId, Message = message },
                cancellationToken: cancellationToken));
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
            logger.LogWarning("Azure DevOps auto-heal pipeline list failed with {StatusCode}: {Body}", (int)response.StatusCode, body);
            return null;
        }

        var list = await DeserializeAsync<PipelineListResponse>(response, cancellationToken);
        var pipeline = list?.Value.FirstOrDefault(item =>
            string.Equals(item.Name, settings.PipelineName, StringComparison.OrdinalIgnoreCase));

        resolvedPipelineId = pipeline?.Id;
        resolvedPipelineName = pipeline?.Name;
        return pipeline?.Id;
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

    private async Task<string> BuildFailureMessageAsync(HttpResponseMessage response, string prefix, CancellationToken cancellationToken)
    {
        var body = await ReadBodySnippetAsync(response, cancellationToken);
        var details = string.IsNullOrWhiteSpace(body)
            ? $"{(int)response.StatusCode} {response.ReasonPhrase}"
            : $"{(int)response.StatusCode} {response.ReasonPhrase}: {body}";

        return $"{prefix} {details}";
    }

    private static async Task<string> ReadBodySnippetAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        return body.Length <= 600 ? body : body[..600];
    }

    private AzureDevOpsSettings GetSettings()
    {
        var section = configuration.GetSection("AzureDevOps");
        var pipelineIdValue =
            section["AutoHealPipelineId"] ??
            configuration["AZDO_AUTOHEAL_PIPELINE_ID"];

        int? pipelineId = null;
        if (int.TryParse(pipelineIdValue, out var parsedPipelineId))
        {
            pipelineId = parsedPipelineId;
        }

        return new AzureDevOpsSettings(
            ReadConfig(section, "Organization", "AZDO_ORGANIZATION"),
            ReadConfig(section, "Project", "AZDO_PROJECT"),
            pipelineId,
            ReadConfig(section, "AutoHealPipelineName", "AZDO_AUTOHEAL_PIPELINE_NAME", DefaultPipelineName),
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

    private static string? NormalizeActionType(string? actionType)
    {
        var cleaned = Clean(actionType);
        if (cleaned is null)
        {
            return null;
        }

        return cleaned.ToLowerInvariant() switch
        {
            "backupretentionscan" or "backupretentionscanandprune" => "BackupRetentionScan",
            "logshrinkassessment" or "logshrink" => "LogShrinkAssessment",
            "deleteselectedbackupfiles" or "cleanupselectedbackupfiles" => "DeleteSelectedBackupFiles",
            _ => null
        };
    }

    private static string? ValidateActionEligibility(string actionType, AutoHealQueueRequest request)
    {
        var alertType = Clean(request.AlertType);
        if (string.Equals(actionType, "BackupRetentionScan", StringComparison.OrdinalIgnoreCase))
        {
            return string.Equals(alertType, "DiskSpaceLow", StringComparison.OrdinalIgnoreCase)
                ? null
                : "Backup cleanup auto-heal is only available for DiskSpaceLow alerts.";
        }

        if (string.Equals(actionType, "LogShrinkAssessment", StringComparison.OrdinalIgnoreCase))
        {
            return alertType is not null && LogShrinkAlertTypes.Contains(alertType)
                ? null
                : "Log shrink auto-heal is only available for log-file alerts.";
        }

        return null;
    }

    private static string? Clean(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static string BuildNotConfiguredMessage(AzureDevOpsSettings settings)
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
            missing.Add("AzureDevOps:AutoHealPipelineId or AzureDevOps:AutoHealPipelineName");
        }

        return $"Auto-heal pipeline trigger is not configured. Missing: {string.Join(", ", missing)}.";
    }

    private static AutoHealRequestStatus BuildImmediateFailure(AutoHealQueueRequest request, string message)
    {
        return new AutoHealRequestStatus
        {
            RequestId = Guid.Empty,
            RequestedAt = DateTime.UtcNow,
            AlertId = request.AlertId,
            AlertType = request.AlertType,
            ServerName = request.ServerName,
            DatabaseName = request.DatabaseName,
            ActionType = request.ActionType,
            TargetPath = request.TargetPath,
            RetentionDays = request.RetentionDays,
            Status = "InvalidRequest",
            IsRunning = false,
            IsConfigured = true,
            Message = message
        };
    }

    private static AutoHealRequestStatus BuildMissingStatus(Guid requestId)
    {
        return new AutoHealRequestStatus
        {
            RequestId = requestId,
            RequestedAt = DateTime.UtcNow,
            Status = "Unknown",
            IsRunning = false,
            Message = "Auto-heal request was created but could not be loaded."
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
