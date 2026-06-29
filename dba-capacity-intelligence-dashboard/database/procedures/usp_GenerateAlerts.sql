USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_GenerateAlerts
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @runStartedAt DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @maxLogFileMb DECIMAL(18,2) = 2097152.00; -- 2 TB SQL Server log file practical cap.

    BEGIN TRY
        BEGIN TRANSACTION;

        CREATE TABLE #GeneratedAlerts
        (
            generated_alert_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
            alert_key NVARCHAR(512) NOT NULL,
            server_name SYSNAME NOT NULL,
            database_name SYSNAME NULL,
            alert_type VARCHAR(100) NOT NULL,
            severity VARCHAR(20) NOT NULL,
            message NVARCHAR(2000) NOT NULL,
            source_script NVARCHAR(260) NULL,
            details_json NVARCHAR(MAX) NULL
        );

        ;WITH RankedForecast AS
        (
            SELECT
                f.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY f.server_name, f.database_name
                    ORDER BY f.calculation_time DESC, f.id DESC
                ) AS rn
            FROM dbo.CapacityForecastResult AS f
        ),
        LatestForecast AS
        (
            SELECT *
            FROM RankedForecast
            WHERE rn = 1
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'CapacityRisk|', f.server_name, N'|', ISNULL(f.database_name, N'')),
            f.server_name,
            f.database_name,
            'CapacityRisk',
            f.risk_level,
            CONCAT(f.database_name, ' is ', f.risk_level, '. ', f.recommendation),
            N'Run-Forecast.ps1; usp_GenerateCapacityForecast.sql; usp_GenerateAlerts.sql',
            (
                SELECT
                    'CapacityRisk' AS category,
                    f.server_name AS serverName,
                    f.database_name AS databaseName,
                    f.current_size_gb AS currentSizeGb,
                    f.growth_7d_gb AS growth7DaysGb,
                    f.growth_30d_gb AS growth30DaysGb,
                    f.avg_growth_per_day_30d_gb AS averageGrowthPerDayGb,
                    f.available_space_gb AS availableSpaceGb,
                    f.estimated_days_remaining AS estimatedDaysRemaining,
                    f.risk_level AS riskLevel,
                    f.recommendation,
                    'dbo.CapacityForecastResult' AS evidenceTable,
                    'Run-Forecast.ps1; usp_GenerateCapacityForecast.sql; usp_GenerateAlerts.sql' AS sourceScripts
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestForecast AS f
        WHERE f.risk_level IN ('Critical', 'High');

        ;WITH LatestLogFileRows AS
        (
            SELECT
                f.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY f.server_name, f.database_name, f.logical_file_name
                    ORDER BY f.collection_time DESC, f.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS f
            WHERE f.file_type = 'LOG'
        ),
        LatestLogFiles AS
        (
            SELECT *
            FROM LatestLogFileRows
            WHERE rn = 1
        ),
        LogDatabaseState AS
        (
            SELECT
                l.server_name,
                l.database_name,
                MAX(l.collection_time) AS latest_collection_time,
                SUM(l.file_size_mb) / 1024.0 AS current_log_size_gb,
                SUM(ISNULL(l.used_space_mb, 0)) / 1024.0 AS used_log_gb,
                SUM(ISNULL(l.free_space_mb, 0)) / 1024.0 AS free_log_gb,
                MAX(l.recovery_model_desc) AS recovery_model_desc,
                MAX(l.log_reuse_wait_desc) AS log_reuse_wait_desc,
                MAX(l.volume_mount_point) AS sample_volume_mount_point,
                SUM(ISNULL(l.volume_available_gb, 0)) AS observed_volume_available_gb,
                SUM
                (
                    CASE
                        WHEN l.volume_available_gb IS NOT NULL
                        THEN
                            CASE
                                WHEN ISNULL(l.max_size_mb, @maxLogFileMb) < l.file_size_mb + (l.volume_available_gb * 1024.0)
                                THEN ISNULL(l.max_size_mb, @maxLogFileMb)
                                ELSE l.file_size_mb + (l.volume_available_gb * 1024.0)
                            END
                        ELSE ISNULL(l.max_size_mb, @maxLogFileMb)
                    END
                ) / 1024.0 AS effective_log_cap_gb
            FROM LatestLogFiles AS l
            GROUP BY l.server_name, l.database_name
        ),
        HourlyLog AS
        (
            SELECT
                DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0) AS capture_hour,
                server_name,
                database_name,
                SUM(file_size_mb) / 1024.0 AS log_size_gb
            FROM dbo.FileSizeHistory
            WHERE file_type = 'LOG'
            GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, collection_time), 0), server_name, database_name
        ),
        RankedHourlyLog AS
        (
            SELECT
                h.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY h.server_name, h.database_name
                    ORDER BY h.capture_hour DESC
                ) AS rn
            FROM HourlyLog AS h
        ),
        LogGrowth AS
        (
            SELECT
                h.server_name,
                h.database_name,
                h.capture_hour,
                h.log_size_gb,
                p24.capture_hour AS prior_24h_hour,
                p24.log_size_gb AS prior_24h_log_size_gb,
                p7.capture_hour AS prior_7d_hour,
                p7.log_size_gb AS prior_7d_log_size_gb,
                h.log_size_gb - p24.log_size_gb AS growth_24h_gb,
                h.log_size_gb - p7.log_size_gb AS growth_7d_gb,
                DATEDIFF(HOUR, p24.capture_hour, h.capture_hour) AS hours_24h_window,
                DATEDIFF(HOUR, p7.capture_hour, h.capture_hour) AS hours_7d_window
            FROM RankedHourlyLog AS h
            OUTER APPLY
            (
                SELECT TOP (1) p.capture_hour, p.log_size_gb
                FROM HourlyLog AS p
                WHERE p.server_name = h.server_name
                  AND p.database_name = h.database_name
                  AND p.capture_hour <= DATEADD(HOUR, -24, h.capture_hour)
                ORDER BY p.capture_hour DESC
            ) AS p24
            OUTER APPLY
            (
                SELECT TOP (1) p.capture_hour, p.log_size_gb
                FROM HourlyLog AS p
                WHERE p.server_name = h.server_name
                  AND p.database_name = h.database_name
                  AND p.capture_hour <= DATEADD(DAY, -7, h.capture_hour)
                ORDER BY p.capture_hour DESC
            ) AS p7
            WHERE h.rn = 1
        ),
        LogRisk AS
        (
            SELECT
                s.server_name,
                s.database_name,
                s.latest_collection_time,
                s.current_log_size_gb,
                s.used_log_gb,
                s.free_log_gb,
                s.effective_log_cap_gb,
                s.effective_log_cap_gb - s.current_log_size_gb AS remaining_to_cap_gb,
                CASE
                    WHEN s.effective_log_cap_gb > 0
                    THEN s.current_log_size_gb * 100.0 / s.effective_log_cap_gb
                    ELSE NULL
                END AS percent_of_effective_cap,
                s.recovery_model_desc,
                s.log_reuse_wait_desc,
                s.sample_volume_mount_point,
                s.observed_volume_available_gb,
                g.growth_24h_gb,
                g.growth_7d_gb,
                CASE
                    WHEN g.growth_24h_gb > 0 AND g.hours_24h_window > 0
                    THEN g.growth_24h_gb / g.hours_24h_window
                    WHEN g.growth_7d_gb > 0 AND g.hours_7d_window > 0
                    THEN g.growth_7d_gb / g.hours_7d_window
                    ELSE NULL
                END AS growth_per_hour_gb
            FROM LogDatabaseState AS s
            LEFT JOIN LogGrowth AS g
                ON g.server_name = s.server_name
               AND g.database_name = s.database_name
        ),
        LogRiskWithProjection AS
        (
            SELECT
                r.*,
                CASE
                    WHEN r.growth_per_hour_gb > 0
                    THEN r.remaining_to_cap_gb / r.growth_per_hour_gb
                    ELSE NULL
                END AS projected_hours_to_cap
            FROM LogRisk AS r
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'LogFileExhaustionRisk|', r.server_name, N'|', ISNULL(r.database_name, N'')),
            r.server_name,
            r.database_name,
            'LogFileExhaustionRisk',
            CASE
                WHEN r.remaining_to_cap_gb <= 10
                  OR r.percent_of_effective_cap >= 95
                  OR r.projected_hours_to_cap <= 24
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT
            (
                'Transaction log risk for ', r.database_name,
                '. Current log: ', CONVERT(DECIMAL(18,2), r.current_log_size_gb), ' GB; effective cap: ',
                CONVERT(DECIMAL(18,2), r.effective_log_cap_gb), ' GB; remaining: ',
                CONVERT(DECIMAL(18,2), r.remaining_to_cap_gb), ' GB; projected hours to cap: ',
                COALESCE(CONVERT(VARCHAR(30), CONVERT(DECIMAL(18,2), r.projected_hours_to_cap)), 'unknown'), '.'
            ),
            N'Collect-FileSize.ps1; Collect-DiskSpace.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'LogFileExhaustionRisk' AS category,
                    r.server_name AS serverName,
                    r.database_name AS databaseName,
                    r.current_log_size_gb AS currentLogSizeGb,
                    r.used_log_gb AS usedLogGb,
                    r.free_log_gb AS freeLogGb,
                    r.effective_log_cap_gb AS effectiveLogCapGb,
                    r.remaining_to_cap_gb AS remainingToCapGb,
                    r.percent_of_effective_cap AS percentOfEffectiveCap,
                    r.growth_24h_gb AS growth24HoursGb,
                    r.growth_7d_gb AS growth7DaysGb,
                    r.growth_per_hour_gb AS growthPerHourGb,
                    r.projected_hours_to_cap AS projectedHoursToCap,
                    r.recovery_model_desc AS recoveryModel,
                    r.log_reuse_wait_desc AS logReuseWait,
                    r.sample_volume_mount_point AS sampleVolumeMountPoint,
                    r.observed_volume_available_gb AS observedVolumeAvailableGb,
                    @maxLogFileMb / 1024.0 AS sqlServerLogFileCapGb,
                    'Effective cap is the lower of explicit max log size, SQL Server 2 TB log-file cap, and observed disk headroom where volume metadata is available.' AS calculationNote,
                    'Collect-FileSize.ps1; Collect-DiskSpace.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LogRiskWithProjection AS r
        WHERE
        (
            r.remaining_to_cap_gb <= 20
            OR r.percent_of_effective_cap >= 85
            OR r.projected_hours_to_cap <= 72
            OR (r.growth_24h_gb >= 10 AND r.remaining_to_cap_gb <= r.growth_24h_gb * 3)
        );

        ;WITH LatestDatabaseSizeRows AS
        (
            SELECT
                d.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY d.server_name, d.database_name
                    ORDER BY d.collection_time DESC, d.id DESC
                ) AS rn
            FROM dbo.DatabaseSizeHistory AS d
        ),
        LatestDatabaseSize AS
        (
            SELECT
                d.server_name,
                d.database_name,
                d.collection_time AS database_size_collection_time,
                d.total_size_mb / 1024.0 AS total_size_gb,
                d.data_size_mb / 1024.0 AS data_size_gb,
                d.log_size_mb / 1024.0 AS database_reported_log_size_gb
            FROM LatestDatabaseSizeRows AS d
            WHERE d.rn = 1
        ),
        LatestLogFileRows AS
        (
            SELECT
                f.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY f.server_name, f.database_name, f.logical_file_name
                    ORDER BY f.collection_time DESC, f.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS f
            WHERE f.file_type = 'LOG'
        ),
        LatestLogFiles AS
        (
            SELECT *
            FROM LatestLogFileRows
            WHERE rn = 1
        ),
        LargeLogSummary AS
        (
            SELECT
                l.server_name,
                l.database_name,
                MAX(l.collection_time) AS latest_collection_time,
                SUM(l.file_size_mb) / 1024.0 AS current_log_size_gb,
                SUM(ISNULL(l.used_space_mb, 0)) / 1024.0 AS used_log_gb,
                SUM(ISNULL(l.free_space_mb, 0)) / 1024.0 AS free_log_gb,
                MAX(l.recovery_model_desc) AS recovery_model_desc,
                MAX(l.log_reuse_wait_desc) AS log_reuse_wait_desc,
                MAX(l.volume_mount_point) AS sample_volume_mount_point,
                SUM(ISNULL(l.volume_available_gb, 0)) AS observed_volume_available_gb,
                SUM
                (
                    CASE
                        WHEN l.volume_available_gb IS NOT NULL
                        THEN
                            CASE
                                WHEN ISNULL(l.max_size_mb, @maxLogFileMb) < l.file_size_mb + (l.volume_available_gb * 1024.0)
                                THEN ISNULL(l.max_size_mb, @maxLogFileMb)
                                ELSE l.file_size_mb + (l.volume_available_gb * 1024.0)
                            END
                        ELSE ISNULL(l.max_size_mb, @maxLogFileMb)
                    END
                ) / 1024.0 AS effective_log_cap_gb
            FROM LatestLogFiles AS l
            GROUP BY l.server_name, l.database_name
        ),
        LargeLogRisk AS
        (
            SELECT
                s.server_name,
                inv.environment,
                s.database_name,
                s.latest_collection_time,
                d.database_size_collection_time,
                s.current_log_size_gb,
                s.used_log_gb,
                s.free_log_gb,
                d.total_size_gb,
                d.data_size_gb,
                d.database_reported_log_size_gb,
                CASE
                    WHEN d.data_size_gb > 0
                    THEN s.current_log_size_gb / d.data_size_gb
                    ELSE NULL
                END AS log_to_data_ratio,
                s.effective_log_cap_gb,
                CASE
                    WHEN s.effective_log_cap_gb > 0
                    THEN s.current_log_size_gb * 100.0 / s.effective_log_cap_gb
                    ELSE NULL
                END AS percent_of_effective_cap,
                s.recovery_model_desc,
                s.log_reuse_wait_desc,
                s.sample_volume_mount_point,
                s.observed_volume_available_gb
            FROM LargeLogSummary AS s
            LEFT JOIN LatestDatabaseSize AS d
                ON d.server_name = s.server_name
               AND d.database_name = s.database_name
            OUTER APPLY
            (
                SELECT TOP (1)
                    si.environment
                FROM dbo.ServerInventory AS si
                WHERE si.server_name = s.server_name
                   OR
                   (
                       CHARINDEX(N'.', si.server_name) > 0
                       AND LEFT(si.server_name, CHARINDEX(N'.', si.server_name) - 1) = s.server_name
                   )
                ORDER BY CASE WHEN si.server_name = s.server_name THEN 0 ELSE 1 END
            ) AS inv
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'UnusuallyLargeLogFile|', r.server_name, N'|', ISNULL(r.database_name, N'')),
            r.server_name,
            r.database_name,
            'UnusuallyLargeLogFile',
            CASE
                WHEN r.current_log_size_gb >= 512
                  OR r.log_to_data_ratio >= 8
                  OR r.percent_of_effective_cap >= 75
                THEN 'Critical'
                WHEN r.current_log_size_gb >= 128
                  OR r.log_to_data_ratio >= 4
                  OR r.percent_of_effective_cap >= 50
                THEN 'High'
                ELSE 'Medium'
            END,
            CONCAT
            (
                r.database_name,
                ' has an unusually large transaction log. Current log: ',
                CONVERT(DECIMAL(18,2), r.current_log_size_gb),
                ' GB',
                CASE
                    WHEN r.data_size_gb > 0
                    THEN CONCAT
                    (
                        '; data size: ',
                        CONVERT(DECIMAL(18,2), r.data_size_gb),
                        ' GB; log/data ratio: ',
                        CONVERT(DECIMAL(18,2), r.log_to_data_ratio),
                        'x'
                    )
                    ELSE '; data size unavailable'
                END,
                '. Recovery: ',
                COALESCE(r.recovery_model_desc, 'unknown'),
                '; log reuse wait: ',
                COALESCE(r.log_reuse_wait_desc, 'unknown'),
                '.'
            ),
            N'Collect-FileSize.ps1; Collect-DatabaseSize.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'UnusuallyLargeLogFile' AS category,
                    r.server_name AS serverName,
                    r.environment,
                    r.database_name AS databaseName,
                    r.latest_collection_time AS latestFileCollectionTime,
                    r.database_size_collection_time AS latestDatabaseSizeCollectionTime,
                    r.current_log_size_gb AS currentLogSizeGb,
                    r.used_log_gb AS usedLogGb,
                    r.free_log_gb AS freeLogGb,
                    r.total_size_gb AS totalSizeGb,
                    r.data_size_gb AS dataSizeGb,
                    r.database_reported_log_size_gb AS databaseReportedLogSizeGb,
                    r.log_to_data_ratio AS logToDataRatio,
                    r.effective_log_cap_gb AS effectiveLogCapGb,
                    r.percent_of_effective_cap AS percentOfEffectiveCap,
                    r.recovery_model_desc AS recoveryModel,
                    r.log_reuse_wait_desc AS logReuseWait,
                    r.sample_volume_mount_point AS sampleVolumeMountPoint,
                    r.observed_volume_available_gb AS observedVolumeAvailableGb,
                    16.0 AS minimumLogAlertThresholdGb,
                    2.0 AS logToDataRatioAlertThreshold,
                    128.0 AS absoluteLogAlertThresholdGb,
                    512.0 AS criticalLogAlertThresholdGb,
                    @maxLogFileMb / 1024.0 AS sqlServerLogFileCapGb,
                    'Flags log files that are large by absolute size or disproportionately large compared with data size. This is separate from exhaustion risk because an oversized reusable log may not be close to disk/full cap but still needs review.' AS calculationNote,
                    'Collect-FileSize.ps1; Collect-DatabaseSize.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory; dbo.DatabaseSizeHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LargeLogRisk AS r
        WHERE r.current_log_size_gb >= 16
          AND
          (
              r.log_to_data_ratio >= 2
              OR r.current_log_size_gb >= 128
              OR r.percent_of_effective_cap >= 50
          );

        ;WITH LatestLogState AS
        (
            SELECT
                l.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY l.server_name, l.database_name
                    ORDER BY l.collection_time DESC, l.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS l
            WHERE l.file_type = 'LOG'
        ),
        LatestLogBackup AS
        (
            SELECT
                b.server_name,
                b.database_name,
                MAX(b.backup_finish_date) AS last_log_backup_finish_date
            FROM dbo.BackupSizeHistory AS b
            WHERE b.backup_type = 'Log'
            GROUP BY b.server_name, b.database_name
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'FullRecoveryNoLogBackup|', l.server_name, N'|', ISNULL(l.database_name, N'')),
            l.server_name,
            l.database_name,
            'FullRecoveryNoLogBackup',
            CASE
                WHEN b.last_log_backup_finish_date IS NULL
                  OR b.last_log_backup_finish_date < DATEADD(HOUR, -72, SYSUTCDATETIME())
                  OR l.log_reuse_wait_desc = 'LOG_BACKUP'
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT
            (
                l.database_name,
                ' is in FULL recovery but no recent log backup was observed. Last log backup: ',
                COALESCE(CONVERT(VARCHAR(30), b.last_log_backup_finish_date, 120), 'none in collected backup history'),
                '. Log reuse wait: ', COALESCE(l.log_reuse_wait_desc, 'unknown'), '.'
            ),
            N'Collect-FileSize.ps1; Collect-BackupSize.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'FullRecoveryNoLogBackup' AS category,
                    l.server_name AS serverName,
                    l.database_name AS databaseName,
                    l.recovery_model_desc AS recoveryModel,
                    l.log_reuse_wait_desc AS logReuseWait,
                    l.file_size_mb / 1024.0 AS currentLogSizeGb,
                    b.last_log_backup_finish_date AS lastLogBackupFinishDate,
                    DATEDIFF(HOUR, b.last_log_backup_finish_date, SYSUTCDATETIME()) AS hoursSinceLastLogBackup,
                    'FULL recovery requires regular log backups. Without them, the transaction log cannot truncate and may grow until it reaches the configured max, SQL Server file cap, or disk limit.' AS explanation,
                    'Collect-FileSize.ps1; Collect-BackupSize.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory; dbo.BackupSizeHistory' AS evidenceTables
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestLogState AS l
        LEFT JOIN LatestLogBackup AS b
            ON b.server_name = l.server_name
           AND b.database_name = l.database_name
        WHERE l.rn = 1
          AND l.recovery_model_desc = 'FULL'
          AND
          (
              b.last_log_backup_finish_date IS NULL
              OR b.last_log_backup_finish_date < DATEADD(HOUR, -24, SYSUTCDATETIME())
              OR l.log_reuse_wait_desc = 'LOG_BACKUP'
          );

        ;WITH RecentLongTransactions AS
        (
            SELECT
                t.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY t.server_name, t.session_id, t.transaction_id
                    ORDER BY t.collection_time DESC, t.id DESC
                ) AS rn
            FROM dbo.LongRunningTransactionHistory AS t
            WHERE t.collection_time >= DATEADD(HOUR, -2, SYSUTCDATETIME())
        ),
        LatestLongTransactions AS
        (
            SELECT *
            FROM RecentLongTransactions
            WHERE rn = 1
              AND duration_minutes >= 60
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'LongRunningTransaction|', t.server_name, N'|', ISNULL(t.database_name, N''), N'|', CONVERT(NVARCHAR(30), t.session_id), N'|', CONVERT(NVARCHAR(30), t.transaction_id)),
            t.server_name,
            t.database_name,
            'LongRunningTransaction',
            CASE WHEN t.duration_minutes >= 240 THEN 'Critical' ELSE 'High' END,
            CONCAT
            (
                'Session ', t.session_id, ' has an open transaction for ',
                CONVERT(DECIMAL(18,2), t.duration_minutes), ' minutes',
                COALESCE(CONCAT(' in ', t.database_name), ''),
                '. Login: ', COALESCE(t.login_name, 'unknown'), '.'
            ),
            N'Collect-LongRunningTransactions.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'LongRunningTransaction' AS category,
                    t.server_name AS serverName,
                    t.database_name AS databaseName,
                    t.session_id AS sessionId,
                    t.transaction_id AS transactionId,
                    t.transaction_begin_time AS transactionBeginTime,
                    t.duration_minutes AS durationMinutes,
                    t.collection_time AS durationCollectedAt,
                    t.login_name AS loginName,
                    t.host_name AS hostName,
                    t.program_name AS programName,
                    t.transaction_name AS transactionName,
                    t.transaction_type_desc AS transactionType,
                    t.transaction_state_desc AS transactionState,
                    t.command,
                    t.wait_type AS waitType,
                    t.blocking_session_id AS blockingSessionId,
                    t.sql_text AS sqlText,
                    t.query_plan_xml AS queryPlanXml,
                    'Long transactions can prevent log truncation and accelerate log growth, especially in FULL recovery.' AS explanation,
                    'Collect-LongRunningTransactions.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.LongRunningTransactionHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestLongTransactions AS t;

        ;WITH LatestBlockedRows AS
        (
            SELECT
                b.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY b.server_name, b.lead_blocker_session_id, b.blocked_session_id
                    ORDER BY b.collection_time DESC, b.id DESC
                ) AS rn
            FROM dbo.BlockingSessionHistory AS b
            WHERE b.collection_time >= DATEADD(MINUTE, -30, SYSUTCDATETIME())
        ),
        CurrentBlocked AS
        (
            SELECT *
            FROM LatestBlockedRows
            WHERE rn = 1
        ),
        BlockerSummary AS
        (
            SELECT
                b.server_name,
                b.lead_blocker_session_id,
                COUNT(DISTINCT b.blocked_session_id) AS blocked_session_count,
                MAX(ISNULL(b.blocked_wait_duration_ms, 0)) AS max_blocked_wait_ms,
                MAX(ISNULL(b.lead_blocker_duration_minutes, 0)) AS lead_blocker_duration_minutes
            FROM CurrentBlocked AS b
            GROUP BY b.server_name, b.lead_blocker_session_id
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'BlockingChain|', s.server_name, N'|', CONVERT(NVARCHAR(30), s.lead_blocker_session_id)),
            s.server_name,
            latest_blocker.database_name,
            'BlockingChain',
            CASE
                WHEN s.blocked_session_count >= 5
                  OR s.max_blocked_wait_ms >= 600000
                  OR s.lead_blocker_duration_minutes >= 30
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT
            (
                'Lead blocker session ', s.lead_blocker_session_id,
                ' is blocking ', s.blocked_session_count, ' session(s). Max blocked wait: ',
                CONVERT(DECIMAL(18,2), s.max_blocked_wait_ms / 1000.0), ' seconds.'
            ),
            N'Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'BlockingChain' AS category,
                    s.server_name AS serverName,
                    s.lead_blocker_session_id AS leadBlockerSessionId,
                    latest_blocker.lead_blocker_login_name AS leadBlockerLoginName,
                    latest_blocker.lead_blocker_host_name AS leadBlockerHostName,
                    latest_blocker.lead_blocker_program_name AS leadBlockerProgramName,
                    latest_blocker.lead_blocker_status AS leadBlockerStatus,
                    latest_blocker.lead_blocker_command AS leadBlockerCommand,
                    latest_blocker.lead_blocker_running_since AS leadBlockerRunningSince,
                    latest_blocker.lead_blocker_duration_minutes AS leadBlockerDurationMinutes,
                    latest_blocker.lead_blocker_transaction_begin_time AS leadBlockerTransactionBeginTime,
                    latest_blocker.lead_blocker_wait_type AS leadBlockerWaitType,
                    latest_blocker.lead_blocker_sql_text AS leadBlockerSqlText,
                    latest_blocker.lead_blocker_query_plan_xml AS leadBlockerQueryPlanXml,
                    s.blocked_session_count AS blockedSessionCount,
                    s.max_blocked_wait_ms AS maxBlockedWaitMs,
                    JSON_QUERY(latest_blocker.blocker_locks_json) AS leadBlockerHeldLocks,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (20)
                                    b.blocked_session_id AS blockedSessionId,
                                    b.database_name AS databaseName,
                                    b.blocked_login_name AS loginName,
                                    b.blocked_host_name AS hostName,
                                    b.blocked_program_name AS programName,
                                    b.blocked_status AS status,
                                    b.blocked_command AS command,
                                    b.blocked_start_time AS requestStartTime,
                                    b.blocked_wait_type AS waitType,
                                    b.blocked_wait_duration_ms AS waitDurationMs,
                                    b.blocked_wait_resource AS waitResource,
                                    b.blocked_object_name AS blockedObjectName,
                                    b.blocked_lock_mode AS blockedLockMode,
                                    b.blocked_sql_text AS blockedSqlText,
                                    b.blocked_query_plan_xml AS blockedQueryPlanXml
                                FROM CurrentBlocked AS b
                                WHERE b.server_name = s.server_name
                                  AND b.lead_blocker_session_id = s.lead_blocker_session_id
                                ORDER BY ISNULL(b.blocked_wait_duration_ms, 0) DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS blockedSessions,
                    'Blocked object is derived from waiting lock metadata when SQL Server exposes the object or HoBT id. Lead blocker held locks show the tables/objects where the blocker currently owns locks.' AS explanation,
                    'Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.BlockingSessionHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM BlockerSummary AS s
        OUTER APPLY
        (
            SELECT TOP (1) b.*
            FROM CurrentBlocked AS b
            WHERE b.server_name = s.server_name
              AND b.lead_blocker_session_id = s.lead_blocker_session_id
            ORDER BY b.collection_time DESC, ISNULL(b.blocked_wait_duration_ms, 0) DESC
        ) AS latest_blocker;

        ;WITH LatestLogState AS
        (
            SELECT
                l.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY l.server_name, l.database_name
                    ORDER BY l.collection_time DESC, l.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS l
            WHERE l.file_type = 'LOG'
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'ActiveTransactionLogReuseWait|', l.server_name, N'|', ISNULL(l.database_name, N'')),
            l.server_name,
            l.database_name,
            'ActiveTransactionLogReuseWait',
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM dbo.BlockingSessionHistory AS b
                    WHERE b.server_name = l.server_name
                      AND ISNULL(b.database_name, N'') = ISNULL(l.database_name, N'')
                      AND b.collection_time >= DATEADD(MINUTE, -30, SYSUTCDATETIME())
                )
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT(l.database_name, ' log reuse is waiting on ACTIVE_TRANSACTION. Check long transactions and blocking evidence.'),
            N'Collect-FileSize.ps1; Collect-LongRunningTransactions.ps1; Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'ActiveTransactionLogReuseWait' AS category,
                    l.server_name AS serverName,
                    l.database_name AS databaseName,
                    l.recovery_model_desc AS recoveryModel,
                    l.log_reuse_wait_desc AS logReuseWait,
                    l.file_size_mb / 1024.0 AS currentLogSizeGb,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (10)
                                    b.lead_blocker_session_id AS leadBlockerSessionId,
                                    b.blocked_session_id AS blockedSessionId,
                                    b.blocked_wait_type AS waitType,
                                    b.blocked_wait_duration_ms AS waitDurationMs,
                                    b.blocked_object_name AS blockedObjectName,
                                    b.lead_blocker_login_name AS leadBlockerLoginName,
                                    b.lead_blocker_sql_text AS leadBlockerSqlText,
                                    b.lead_blocker_query_plan_xml AS leadBlockerQueryPlanXml,
                                    b.blocked_sql_text AS blockedSqlText,
                                    b.blocked_query_plan_xml AS blockedQueryPlanXml
                                FROM dbo.BlockingSessionHistory AS b
                                WHERE b.server_name = l.server_name
                                  AND ISNULL(b.database_name, N'') = ISNULL(l.database_name, N'')
                                  AND b.collection_time >= DATEADD(MINUTE, -30, SYSUTCDATETIME())
                                ORDER BY ISNULL(b.blocked_wait_duration_ms, 0) DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS blockingEvidence,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (10)
                                    t.session_id AS sessionId,
                                    t.transaction_id AS transactionId,
                                    t.transaction_begin_time AS transactionBeginTime,
                                    t.duration_minutes AS durationMinutes,
                                    t.login_name AS loginName,
                                    t.host_name AS hostName,
                                    t.program_name AS programName,
                                    t.sql_text AS sqlText,
                                    t.query_plan_xml AS queryPlanXml
                                FROM dbo.LongRunningTransactionHistory AS t
                                WHERE t.server_name = l.server_name
                                  AND ISNULL(t.database_name, N'') = ISNULL(l.database_name, N'')
                                  AND t.collection_time >= DATEADD(HOUR, -2, SYSUTCDATETIME())
                                ORDER BY ISNULL(t.duration_minutes, 0) DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS longRunningTransactions,
                    'ACTIVE_TRANSACTION means log truncation is waiting for an open transaction. Blocking rows identify the lead blocker and blocked sessions when blocking is present.' AS explanation,
                    'Collect-FileSize.ps1; Collect-LongRunningTransactions.ps1; Collect-BlockingSessions.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory; dbo.LongRunningTransactionHistory; dbo.BlockingSessionHistory' AS evidenceTables
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestLogState AS l
        WHERE l.rn = 1
          AND l.log_reuse_wait_desc = 'ACTIVE_TRANSACTION';

        ;WITH LatestAlwaysOnRows AS
        (
            SELECT
                aoh.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY aoh.server_name, aoh.availability_group_name, aoh.replica_server_name, ISNULL(aoh.database_name, N'')
                    ORDER BY aoh.collection_time DESC, aoh.id DESC
                ) AS rn
            FROM dbo.AlwaysOnHealthHistory AS aoh
            WHERE aoh.collection_time >= DATEADD(MINUTE, -30, SYSUTCDATETIME())
        ),
        CurrentAlwaysOn AS
        (
            SELECT *
            FROM LatestAlwaysOnRows
            WHERE rn = 1
        ),
        AlwaysOnIssues AS
        (
            SELECT *
            FROM CurrentAlwaysOn
            WHERE ISNULL(connected_state_desc, N'CONNECTED') <> N'CONNECTED'
               OR ISNULL(replica_synchronization_health_desc, N'HEALTHY') <> N'HEALTHY'
               OR ISNULL(database_synchronization_health_desc, N'HEALTHY') <> N'HEALTHY'
               OR ISNULL(database_synchronization_state_desc, N'SYNCHRONIZED') NOT IN (N'SYNCHRONIZED', N'SYNCHRONIZING')
               OR ISNULL(is_suspended, 0) = 1
               OR last_connect_error_number IS NOT NULL
        ),
        AlwaysOnSummary AS
        (
            SELECT
                server_name,
                availability_group_name,
                replica_server_name,
                COUNT(*) AS issue_count,
                SUM(CASE WHEN database_name IS NOT NULL THEN 1 ELSE 0 END) AS database_issue_count,
                MAX(CASE WHEN connected_state_desc = N'DISCONNECTED' OR last_connect_error_number IS NOT NULL THEN 1 ELSE 0 END) AS has_connectivity_issue,
                MAX(CASE WHEN ISNULL(is_suspended, 0) = 1 THEN 1 ELSE 0 END) AS has_suspended_database
            FROM AlwaysOnIssues
            GROUP BY server_name, availability_group_name, replica_server_name
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'AlwaysOnHealthIssue|', s.server_name, N'|', ISNULL(s.availability_group_name, N''), N'|', ISNULL(s.replica_server_name, N'')),
            s.server_name,
            latest_issue.database_name,
            'AlwaysOnHealthIssue',
            CASE
                WHEN s.has_connectivity_issue = 1 OR s.has_suspended_database = 1 THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT
            (
                'Always On issue in AG ', COALESCE(s.availability_group_name, 'unknown'),
                ' on replica ', COALESCE(s.replica_server_name, 'unknown'),
                '. Database issues: ', s.database_issue_count,
                '; connectivity issue: ', CASE WHEN s.has_connectivity_issue = 1 THEN 'yes' ELSE 'no' END, '.'
            ),
            N'Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'AlwaysOnHealthIssue' AS category,
                    s.server_name AS serverName,
                    s.availability_group_name AS availabilityGroupName,
                    s.replica_server_name AS replicaServerName,
                    latest_issue.role_desc AS role,
                    latest_issue.operational_state_desc AS operationalState,
                    latest_issue.connected_state_desc AS connectedState,
                    latest_issue.replica_synchronization_health_desc AS replicaSynchronizationHealth,
                    s.issue_count AS issueCount,
                    s.database_issue_count AS databaseIssueCount,
                    s.has_connectivity_issue AS hasConnectivityIssue,
                    latest_issue.last_connect_error_number AS lastConnectErrorNumber,
                    latest_issue.last_connect_error_description AS lastConnectErrorDescription,
                    latest_issue.last_connect_error_timestamp AS lastConnectErrorTimestamp,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (20)
                                    i.database_name AS databaseName,
                                    i.database_synchronization_state_desc AS synchronizationState,
                                    i.database_synchronization_health_desc AS synchronizationHealth,
                                    i.database_state_desc AS databaseState,
                                    i.is_suspended AS isSuspended,
                                    i.suspend_reason_desc AS suspendReason,
                                    i.log_send_queue_size_kb AS logSendQueueSizeKb,
                                    i.redo_queue_size_kb AS redoQueueSizeKb,
                                    i.last_sent_time AS lastSentTime,
                                    i.last_received_time AS lastReceivedTime,
                                    i.last_hardened_time AS lastHardenedTime,
                                    i.last_redone_time AS lastRedoneTime,
                                    i.last_commit_time AS lastCommitTime
                                FROM AlwaysOnIssues AS i
                                WHERE i.server_name = s.server_name
                                  AND ISNULL(i.availability_group_name, N'') = ISNULL(s.availability_group_name, N'')
                                  AND ISNULL(i.replica_server_name, N'') = ISNULL(s.replica_server_name, N'')
                                ORDER BY i.database_name
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS databaseIssues,
                    'These fields come from Always On dashboard-equivalent DMVs. DISCONNECTED state or last connect errors usually indicate connectivity, endpoint, DNS, firewall, or service-account issues. Suspended or unhealthy database rows identify database-specific synchronization problems.' AS explanation,
                    'Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.AlwaysOnHealthHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM AlwaysOnSummary AS s
        OUTER APPLY
        (
            SELECT TOP (1) i.*
            FROM AlwaysOnIssues AS i
            WHERE i.server_name = s.server_name
              AND ISNULL(i.availability_group_name, N'') = ISNULL(s.availability_group_name, N'')
              AND ISNULL(i.replica_server_name, N'') = ISNULL(s.replica_server_name, N'')
            ORDER BY
                CASE WHEN i.connected_state_desc = N'DISCONNECTED' OR i.last_connect_error_number IS NOT NULL THEN 0 ELSE 1 END,
                CASE WHEN ISNULL(i.is_suspended, 0) = 1 THEN 0 ELSE 1 END,
                i.collection_time DESC
        ) AS latest_issue;

        ;WITH LatestLogState AS
        (
            SELECT
                l.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY l.server_name, l.database_name
                    ORDER BY l.collection_time DESC, l.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS l
            WHERE l.file_type = 'LOG'
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'AlwaysOnLogReuseWait|', l.server_name, N'|', ISNULL(l.database_name, N'')),
            l.server_name,
            l.database_name,
            'AlwaysOnLogReuseWait',
            'High',
            CONCAT(l.database_name, ' log reuse is waiting on AVAILABILITY_REPLICA. Check Always On synchronization evidence.'),
            N'Collect-FileSize.ps1; Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'AlwaysOnLogReuseWait' AS category,
                    l.server_name AS serverName,
                    l.database_name AS databaseName,
                    l.recovery_model_desc AS recoveryModel,
                    l.log_reuse_wait_desc AS logReuseWait,
                    l.file_size_mb / 1024.0 AS currentLogSizeGb,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (20)
                                    aoh.availability_group_name AS availabilityGroupName,
                                    aoh.replica_server_name AS replicaServerName,
                                    aoh.role_desc AS role,
                                    aoh.connected_state_desc AS connectedState,
                                    aoh.replica_synchronization_health_desc AS replicaSynchronizationHealth,
                                    aoh.database_synchronization_state_desc AS databaseSynchronizationState,
                                    aoh.database_synchronization_health_desc AS databaseSynchronizationHealth,
                                    aoh.is_suspended AS isSuspended,
                                    aoh.suspend_reason_desc AS suspendReason,
                                    aoh.log_send_queue_size_kb AS logSendQueueSizeKb,
                                    aoh.redo_queue_size_kb AS redoQueueSizeKb,
                                    aoh.last_connect_error_number AS lastConnectErrorNumber,
                                    aoh.last_connect_error_description AS lastConnectErrorDescription
                                FROM dbo.AlwaysOnHealthHistory AS aoh
                                WHERE aoh.server_name = l.server_name
                                  AND ISNULL(aoh.database_name, N'') = ISNULL(l.database_name, N'')
                                  AND aoh.collection_time >= DATEADD(HOUR, -2, SYSUTCDATETIME())
                                ORDER BY aoh.collection_time DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS alwaysOnEvidence,
                    'AVAILABILITY_REPLICA means log truncation is waiting for an availability replica. Check disconnected replicas, send/redo queues, suspended databases, and connect errors.' AS explanation,
                    'Collect-FileSize.ps1; Collect-AlwaysOnHealth.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory; dbo.AlwaysOnHealthHistory' AS evidenceTables
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestLogState AS l
        WHERE l.rn = 1
          AND l.log_reuse_wait_desc = 'AVAILABILITY_REPLICA';

        ;WITH LatestReplicationRows AS
        (
            SELECT
                rh.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY rh.server_name, ISNULL(rh.database_name, N''), ISNULL(rh.publication, N''), ISNULL(rh.agent_type, N''), ISNULL(rh.agent_name, N'')
                    ORDER BY rh.collection_time DESC, rh.id DESC
                ) AS rn
            FROM dbo.ReplicationHealthHistory AS rh
            WHERE rh.collection_time >= DATEADD(HOUR, -2, SYSUTCDATETIME())
        ),
        CurrentReplication AS
        (
            SELECT *
            FROM LatestReplicationRows
            WHERE rn = 1
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'ReplicationAgentIssue|', rh.server_name, N'|', ISNULL(rh.database_name, N''), N'|', ISNULL(rh.publication, N''), N'|', ISNULL(rh.agent_type, N''), N'|', ISNULL(rh.agent_name, N'')),
            rh.server_name,
            rh.database_name,
            'ReplicationAgentIssue',
            CASE WHEN rh.run_status = 6 OR rh.run_status_desc = N'Failed' THEN 'Critical' ELSE 'High' END,
            CONCAT
            (
                COALESCE(rh.agent_type, 'Replication'), ' agent ',
                COALESCE(rh.agent_name, 'unknown'),
                ' is ', COALESCE(rh.run_status_desc, 'not reporting healthy status'),
                COALESCE(CONCAT('. Error: ', NULLIF(LEFT(COALESCE(rh.error_text, rh.comments), 250), N'')), '.')
            ),
            N'Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'ReplicationAgentIssue' AS category,
                    rh.server_name AS serverName,
                    rh.database_name AS databaseName,
                    rh.publication,
                    rh.agent_type AS agentType,
                    rh.agent_name AS agentName,
                    rh.subscriber_name AS subscriberName,
                    rh.subscriber_database_name AS subscriberDatabaseName,
                    rh.run_status AS runStatus,
                    rh.run_status_desc AS runStatusDescription,
                    rh.last_event_time AS lastEventTime,
                    rh.latency_seconds AS latencySeconds,
                    rh.delivered_commands AS deliveredCommands,
                    rh.delivery_rate AS deliveryRate,
                    rh.error_id AS errorId,
                    rh.error_code AS errorCode,
                    rh.error_text AS errorText,
                    rh.comments,
                    'Replication agent state is read from the local distribution database when this instance hosts distribution metadata. Failed or retrying agents can prevent replicated transactions from clearing and may hold log truncation.' AS explanation,
                    'Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.ReplicationHealthHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM CurrentReplication AS rh
        WHERE rh.agent_type <> N'DatabaseFlag'
          AND
          (
              rh.run_status IN (5, 6)
              OR rh.run_status_desc IN (N'Retry', N'Failed')
              OR rh.error_id IS NOT NULL
              OR rh.error_code IS NOT NULL
          );

        ;WITH LatestLogState AS
        (
            SELECT
                l.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY l.server_name, l.database_name
                    ORDER BY l.collection_time DESC, l.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS l
            WHERE l.file_type = 'LOG'
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'ReplicationLogReuseWait|', l.server_name, N'|', ISNULL(l.database_name, N'')),
            l.server_name,
            l.database_name,
            'ReplicationLogReuseWait',
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM dbo.ReplicationHealthHistory AS rh
                    WHERE rh.server_name = l.server_name
                      AND ISNULL(rh.database_name, N'') = ISNULL(l.database_name, N'')
                      AND rh.collection_time >= DATEADD(HOUR, -2, SYSUTCDATETIME())
                      AND (rh.run_status IN (5, 6) OR rh.error_id IS NOT NULL OR rh.error_code IS NOT NULL)
                )
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT(l.database_name, ' log reuse is waiting on REPLICATION. Check replication agent and distribution evidence.'),
            N'Collect-FileSize.ps1; Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'ReplicationLogReuseWait' AS category,
                    l.server_name AS serverName,
                    l.database_name AS databaseName,
                    l.recovery_model_desc AS recoveryModel,
                    l.log_reuse_wait_desc AS logReuseWait,
                    l.file_size_mb / 1024.0 AS currentLogSizeGb,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (20)
                                    rh.publication,
                                    rh.agent_type AS agentType,
                                    rh.agent_name AS agentName,
                                    rh.subscriber_name AS subscriberName,
                                    rh.subscriber_database_name AS subscriberDatabaseName,
                                    rh.run_status_desc AS runStatusDescription,
                                    rh.last_event_time AS lastEventTime,
                                    rh.latency_seconds AS latencySeconds,
                                    rh.delivered_commands AS deliveredCommands,
                                    rh.error_code AS errorCode,
                                    rh.error_text AS errorText,
                                    rh.comments
                                FROM dbo.ReplicationHealthHistory AS rh
                                WHERE rh.server_name = l.server_name
                                  AND ISNULL(rh.database_name, N'') = ISNULL(l.database_name, N'')
                                  AND rh.collection_time >= DATEADD(HOUR, -4, SYSUTCDATETIME())
                                ORDER BY rh.collection_time DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS replicationEvidence,
                    'REPLICATION means log truncation is waiting for transactional replication to consume log records. Check failed/retrying Log Reader or Distribution agents, subscriber reachability, and distribution backlog.' AS explanation,
                    'Collect-FileSize.ps1; Collect-ReplicationHealth.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.FileSizeHistory; dbo.ReplicationHealthHistory' AS evidenceTables
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestLogState AS l
        WHERE l.rn = 1
          AND l.log_reuse_wait_desc = 'REPLICATION';

        ;WITH LatestTempDb AS
        (
            SELECT
                t.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY t.server_name
                    ORDER BY t.collection_time DESC, t.id DESC
                ) AS rn
            FROM dbo.TempDBUsageHistory AS t
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'TempDBUsage|', t.server_name),
            t.server_name,
            'tempdb',
            'TempDBUsage',
            CASE
                WHEN ((t.tempdb_size_mb - ISNULL(t.free_space_mb, 0)) * 100.0 / NULLIF(t.tempdb_size_mb, 0)) >= 95
                THEN 'Critical'
                ELSE 'High'
            END,
            CONCAT('TempDB usage is ', CONVERT(DECIMAL(18,2), ((t.tempdb_size_mb - t.free_space_mb) * 100.0 / NULLIF(t.tempdb_size_mb, 0))), ' percent.'),
            N'Collect-TempDBUsage.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'TempDBUsage' AS category,
                    t.server_name AS serverName,
                    t.tempdb_size_mb AS tempdbSizeMb,
                    t.user_objects_mb AS userObjectsMb,
                    t.internal_objects_mb AS internalObjectsMb,
                    t.version_store_mb AS versionStoreMb,
                    t.free_space_mb AS freeSpaceMb,
                    (t.tempdb_size_mb - ISNULL(t.free_space_mb, 0)) AS usedSpaceMb,
                    ((t.tempdb_size_mb - ISNULL(t.free_space_mb, 0)) * 100.0 / NULLIF(t.tempdb_size_mb, 0)) AS usedPercent,
                    JSON_QUERY
                    (
                        COALESCE
                        (
                            (
                                SELECT TOP (5)
                                    c.session_id AS sessionId,
                                    c.request_id AS requestId,
                                    c.database_name AS databaseName,
                                    c.login_name AS loginName,
                                    c.host_name AS hostName,
                                    c.program_name AS programName,
                                    c.status,
                                    c.command,
                                    c.wait_type AS waitType,
                                    c.blocking_session_id AS blockingSessionId,
                                    c.user_objects_mb AS userObjectsMb,
                                    c.internal_objects_mb AS internalObjectsMb,
                                    c.total_allocated_mb AS totalAllocatedMb,
                                    c.sql_text AS sqlText
                                FROM dbo.TempDBSessionUsageHistory AS c
                                WHERE c.server_name = t.server_name
                                  AND c.collection_time >= DATEADD(MINUTE, -30, t.collection_time)
                                ORDER BY c.total_allocated_mb DESC
                                FOR JSON PATH
                            ),
                            N'[]'
                        )
                    ) AS topConsumers,
                    'Top consumers are captured from sys.dm_db_session_space_usage at collection time.' AS explanation,
                    'Collect-TempDBUsage.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.TempDBUsageHistory; dbo.TempDBSessionUsageHistory' AS evidenceTables
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestTempDb AS t
        WHERE t.rn = 1
          AND t.tempdb_size_mb > 0
          AND ((t.tempdb_size_mb - ISNULL(t.free_space_mb, 0)) * 100.0 / t.tempdb_size_mb) >= 80;

        ;WITH LatestDisk AS
        (
            SELECT
                d.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY d.server_name, d.volume_mount_point
                    ORDER BY d.collection_time DESC, d.id DESC
                ) AS rn
            FROM dbo.DiskSpaceHistory AS d
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'DiskSpaceLow|', d.server_name, N'|', ISNULL(d.volume_mount_point, N'')),
            d.server_name,
            NULL,
            'DiskSpaceLow',
            CASE WHEN d.available_gb <= 10 OR d.used_percent >= 95 THEN 'Critical' ELSE 'High' END,
            CONCAT('Volume ', d.volume_mount_point, ' has ', d.available_gb, ' GB available and is ', d.used_percent, ' percent used.'),
            N'Collect-DiskSpace.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'DiskSpaceLow' AS category,
                    d.server_name AS serverName,
                    d.volume_mount_point AS volumeMountPoint,
                    d.logical_volume_name AS logicalVolumeName,
                    d.total_gb AS totalGb,
                    d.available_gb AS availableGb,
                    d.used_gb AS usedGb,
                    d.used_percent AS usedPercent,
                    'Low disk space can prevent data and log file growth.' AS explanation,
                    'Collect-DiskSpace.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.DiskSpaceHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM LatestDisk AS d
        WHERE d.rn = 1
          AND (d.available_gb <= 20 OR d.used_percent >= 90);

        ;WITH RankedBackup AS
        (
            SELECT
                b.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY b.server_name, b.database_name, b.backup_type
                    ORDER BY b.backup_finish_date DESC, b.id DESC
                ) AS rn
            FROM dbo.BackupSizeHistory AS b
            WHERE b.backup_finish_date IS NOT NULL
              AND b.backup_size_gb IS NOT NULL
        ),
        BackupGrowth AS
        (
            SELECT
                b.server_name,
                b.database_name,
                b.backup_type,
                b.backup_size_gb,
                b.backup_finish_date,
                p.avg_backup_size_gb
            FROM RankedBackup AS b
            OUTER APPLY
            (
                SELECT AVG(p.backup_size_gb) AS avg_backup_size_gb
                FROM dbo.BackupSizeHistory AS p
                WHERE p.server_name = b.server_name
                  AND p.database_name = b.database_name
                  AND ISNULL(p.backup_type, '') = ISNULL(b.backup_type, '')
                  AND p.backup_finish_date < b.backup_finish_date
                  AND p.backup_finish_date >= DATEADD(DAY, -30, b.backup_finish_date)
            ) AS p
            WHERE b.rn = 1
        )
        INSERT INTO #GeneratedAlerts
        (
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            CONCAT(N'BackupGrowth|', bg.server_name, N'|', ISNULL(bg.database_name, N''), N'|', ISNULL(bg.backup_type, N'')),
            bg.server_name,
            bg.database_name,
            'BackupGrowth',
            'Medium',
            CONCAT(bg.backup_type, ' backup size increased sharply. Latest: ', bg.backup_size_gb, ' GB, 30-day average: ', CONVERT(DECIMAL(18,2), bg.avg_backup_size_gb), ' GB.'),
            N'Collect-BackupSize.ps1; usp_GenerateAlerts.sql',
            (
                SELECT
                    'BackupGrowth' AS category,
                    bg.server_name AS serverName,
                    bg.database_name AS databaseName,
                    bg.backup_type AS backupType,
                    bg.backup_finish_date AS backupFinishDate,
                    bg.backup_size_gb AS backupSizeGb,
                    bg.avg_backup_size_gb AS averageBackupSizeGb,
                    'Collect-BackupSize.ps1; usp_GenerateAlerts.sql' AS sourceScripts,
                    'dbo.BackupSizeHistory' AS evidenceTable
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )
        FROM BackupGrowth AS bg
        WHERE bg.avg_backup_size_gb IS NOT NULL
          AND bg.backup_size_gb >= bg.avg_backup_size_gb * 1.5
          AND bg.backup_size_gb - bg.avg_backup_size_gb >= 5;

        ;WITH RankedGeneratedAlerts AS
        (
            SELECT
                g.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY g.alert_key
                    ORDER BY g.generated_alert_id DESC
                ) AS rn
            FROM #GeneratedAlerts AS g
        )
        SELECT
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        INTO #CurrentGeneratedAlerts
        FROM RankedGeneratedAlerts
        WHERE rn = 1;

        UPDATE a
            SET alert_time = @runStartedAt,
                server_name = c.server_name,
                database_name = c.database_name,
                alert_type = c.alert_type,
                severity = c.severity,
                message = c.message,
                source_script = c.source_script,
                details_json = c.details_json,
                alert_key = c.alert_key,
                is_resolved = 0,
                resolved_at = NULL
        FROM dbo.AlertHistory AS a
        INNER JOIN #CurrentGeneratedAlerts AS c
            ON c.alert_key = a.alert_key
        WHERE a.is_resolved = 0;

        INSERT INTO dbo.AlertHistory
        (
            alert_time,
            alert_key,
            server_name,
            database_name,
            alert_type,
            severity,
            message,
            source_script,
            details_json
        )
        SELECT
            @runStartedAt,
            c.alert_key,
            c.server_name,
            c.database_name,
            c.alert_type,
            c.severity,
            c.message,
            c.source_script,
            c.details_json
        FROM #CurrentGeneratedAlerts AS c
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.AlertHistory AS a
            WHERE a.is_resolved = 0
              AND a.alert_key = c.alert_key
        );

        UPDATE a
            SET is_resolved = 1,
                resolved_at = COALESCE(a.resolved_at, @runStartedAt)
        FROM dbo.AlertHistory AS a
        WHERE a.is_resolved = 0
          AND a.alert_type IN
          (
              'CapacityRisk',
              'LogFileExhaustionRisk',
              'UnusuallyLargeLogFile',
              'FullRecoveryNoLogBackup',
              'LongRunningTransaction',
              'BlockingChain',
              'ActiveTransactionLogReuseWait',
              'AlwaysOnHealthIssue',
              'AlwaysOnLogReuseWait',
              'ReplicationAgentIssue',
              'ReplicationLogReuseWait',
              'TempDBUsage',
              'DiskSpaceLow',
              'BackupGrowth'
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM #CurrentGeneratedAlerts AS c
              WHERE c.alert_key = a.alert_key
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH;
END;
GO
