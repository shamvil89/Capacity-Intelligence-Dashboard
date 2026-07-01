USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_GenerateCapacityForecast
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @criticalDaysRemaining DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'CriticalDaysRemaining'), 7);
    DECLARE @highDaysRemaining DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'HighDaysRemaining'), 15);
    DECLARE @mediumDaysRemaining DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'MediumDaysRemaining'), 30);
    DECLARE @lowDaysRemaining DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'LowDaysRemaining'), 60);
    DECLARE @criticalGrowthPerDayGb DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'CriticalGrowthPerDayGb'), 20);
    DECLARE @highGrowthPerDayGb DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'HighGrowthPerDayGb'), 10);
    DECLARE @mediumGrowthPerDayGb DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'MediumGrowthPerDayGb'), 5);
    DECLARE @lowGrowthPerDayGb DECIMAL(18,4) = COALESCE((SELECT TOP (1) setting_value_decimal FROM dbo.AlertThresholdSetting WHERE alert_type = 'CapacityRisk' AND setting_key = 'LowGrowthPerDayGb'), 1);

    BEGIN TRY
        ;WITH LatestDb AS
        (
            SELECT
                h.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY h.server_name, h.database_name
                    ORDER BY h.collection_time DESC, h.id DESC
                ) AS rn
            FROM dbo.DatabaseSizeHistory AS h
        ),
        CurrentDb AS
        (
            SELECT *
            FROM LatestDb
            WHERE rn = 1
        ),
        LatestDisk AS
        (
            SELECT
                d.server_name,
                d.volume_mount_point,
                d.available_gb,
                ROW_NUMBER() OVER
                (
                    PARTITION BY d.server_name, d.volume_mount_point
                    ORDER BY d.collection_time DESC, d.id DESC
                ) AS rn
            FROM dbo.DiskSpaceHistory AS d
        ),
        AvailableSpace AS
        (
            SELECT
                server_name,
                MIN(available_gb) AS available_space_gb
            FROM LatestDisk
            WHERE rn = 1
            GROUP BY server_name
        ),
        LatestFile AS
        (
            SELECT
                f.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY f.server_name, f.database_name, f.logical_file_name
                    ORDER BY f.collection_time DESC, f.id DESC
                ) AS rn
            FROM dbo.FileSizeHistory AS f
            WHERE f.volume_mount_point IS NOT NULL
              AND LTRIM(RTRIM(f.volume_mount_point)) <> N''
        ),
        CurrentFile AS
        (
            SELECT *
            FROM LatestFile
            WHERE rn = 1
        ),
        FileGrowth AS
        (
            SELECT
                c.server_name,
                c.database_name,
                c.logical_file_name,
                c.volume_mount_point,
                CAST(c.file_size_mb / 1024.0 AS DECIMAL(18,4)) AS current_file_size_gb,
                CAST
                (
                    CASE
                        WHEN previous_file.file_size_mb IS NULL OR c.file_size_mb <= previous_file.file_size_mb
                            THEN 0
                        ELSE (c.file_size_mb - previous_file.file_size_mb) / 1024.0 / 30.0
                    END AS DECIMAL(18,4)
                ) AS avg_file_growth_per_day_30d_gb,
                COALESCE(d.available_gb, c.volume_available_gb) AS volume_available_gb
            FROM CurrentFile AS c
            OUTER APPLY
            (
                SELECT TOP (1) h.file_size_mb
                FROM dbo.FileSizeHistory AS h
                WHERE h.server_name = c.server_name
                  AND h.database_name = c.database_name
                  AND h.logical_file_name = c.logical_file_name
                  AND h.collection_time < c.collection_time
                ORDER BY ABS(DATEDIFF_BIG(SECOND, h.collection_time, DATEADD(DAY, -30, c.collection_time)))
            ) AS previous_file
            OUTER APPLY
            (
                SELECT TOP (1) ld.available_gb
                FROM LatestDisk AS ld
                WHERE ld.rn = 1
                  AND ld.server_name = c.server_name
                  AND ld.volume_mount_point = c.volume_mount_point
            ) AS d
        ),
        VolumeGrowth AS
        (
            SELECT
                server_name,
                volume_mount_point,
                MIN(volume_available_gb) AS volume_available_gb,
                SUM(avg_file_growth_per_day_30d_gb) AS shared_volume_growth_per_day_30d_gb
            FROM FileGrowth
            GROUP BY server_name, volume_mount_point
        ),
        DbVolumeRisk AS
        (
            SELECT
                fg.server_name,
                fg.database_name,
                fg.volume_mount_point,
                vg.volume_available_gb,
                vg.shared_volume_growth_per_day_30d_gb,
                CAST
                (
                    CASE
                        WHEN vg.volume_available_gb IS NULL
                          OR vg.shared_volume_growth_per_day_30d_gb IS NULL
                          OR vg.shared_volume_growth_per_day_30d_gb <= 0
                            THEN NULL
                        ELSE vg.volume_available_gb / NULLIF(vg.shared_volume_growth_per_day_30d_gb, 0)
                    END AS DECIMAL(18,4)
                ) AS estimated_days_remaining,
                ROW_NUMBER() OVER
                (
                    PARTITION BY fg.server_name, fg.database_name
                    ORDER BY
                        CASE
                            WHEN vg.volume_available_gb IS NULL
                              OR vg.shared_volume_growth_per_day_30d_gb IS NULL
                              OR vg.shared_volume_growth_per_day_30d_gb <= 0
                                THEN 1
                            ELSE 0
                        END,
                        vg.volume_available_gb / NULLIF(vg.shared_volume_growth_per_day_30d_gb, 0),
                        fg.volume_mount_point
                ) AS rn
            FROM
            (
                SELECT DISTINCT server_name, database_name, volume_mount_point
                FROM FileGrowth
            ) AS fg
            INNER JOIN VolumeGrowth AS vg
                ON vg.server_name = fg.server_name
               AND vg.volume_mount_point = fg.volume_mount_point
        ),
        LimitingVolume AS
        (
            SELECT
                server_name,
                database_name,
                volume_mount_point,
                volume_available_gb,
                shared_volume_growth_per_day_30d_gb,
                estimated_days_remaining
            FROM DbVolumeRisk
            WHERE rn = 1
        ),
        Growth AS
        (
            SELECT
                c.server_name,
                c.database_name,
                CAST(c.total_size_mb / 1024.0 AS DECIMAL(18,2)) AS current_size_gb,
                CAST((c.total_size_mb - d7.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_7d_gb,
                CAST((c.total_size_mb - d30.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_30d_gb,
                CAST((c.total_size_mb - d90.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_90d_gb,
                CAST((c.total_size_mb - d7.total_size_mb) / 1024.0 / 7.0 AS DECIMAL(18,4)) AS avg_growth_per_day_7d_gb,
                CAST((c.total_size_mb - d30.total_size_mb) / 1024.0 / 30.0 AS DECIMAL(18,4)) AS avg_growth_per_day_30d_gb,
                CAST((c.total_size_mb - d90.total_size_mb) / 1024.0 / 90.0 AS DECIMAL(18,4)) AS avg_growth_per_day_90d_gb,
                COALESCE(lv.volume_available_gb, a.available_space_gb) AS available_space_gb,
                lv.volume_mount_point AS limiting_volume_mount_point,
                lv.shared_volume_growth_per_day_30d_gb,
                CASE
                    WHEN lv.estimated_days_remaining IS NOT NULL THEN 'SharedDriveGrowth'
                    WHEN a.available_space_gb IS NOT NULL THEN 'DatabaseGrowthFallback'
                    ELSE 'InsufficientDiskData'
                END AS forecast_method
            FROM CurrentDb AS c
            OUTER APPLY
            (
                SELECT TOP (1) h.total_size_mb
                FROM dbo.DatabaseSizeHistory AS h
                WHERE h.server_name = c.server_name
                  AND h.database_name = c.database_name
                  AND h.collection_time < c.collection_time
                ORDER BY ABS(DATEDIFF_BIG(SECOND, h.collection_time, DATEADD(DAY, -7, c.collection_time)))
            ) AS d7
            OUTER APPLY
            (
                SELECT TOP (1) h.total_size_mb
                FROM dbo.DatabaseSizeHistory AS h
                WHERE h.server_name = c.server_name
                  AND h.database_name = c.database_name
                  AND h.collection_time < c.collection_time
                ORDER BY ABS(DATEDIFF_BIG(SECOND, h.collection_time, DATEADD(DAY, -30, c.collection_time)))
            ) AS d30
            OUTER APPLY
            (
                SELECT TOP (1) h.total_size_mb
                FROM dbo.DatabaseSizeHistory AS h
                WHERE h.server_name = c.server_name
                  AND h.database_name = c.database_name
                  AND h.collection_time < c.collection_time
                ORDER BY ABS(DATEDIFF_BIG(SECOND, h.collection_time, DATEADD(DAY, -90, c.collection_time)))
            ) AS d90
            LEFT JOIN AvailableSpace AS a
                ON a.server_name = c.server_name
            LEFT JOIN LimitingVolume AS lv
                ON lv.server_name = c.server_name
               AND lv.database_name = c.database_name
        ),
        Scored AS
        (
            SELECT
                g.*,
                CAST
                (
                    CASE
                        WHEN g.shared_volume_growth_per_day_30d_gb IS NOT NULL
                          AND g.shared_volume_growth_per_day_30d_gb > 0
                          AND g.available_space_gb IS NOT NULL
                            THEN g.available_space_gb / NULLIF(g.shared_volume_growth_per_day_30d_gb, 0)
                        WHEN g.available_space_gb IS NULL
                          OR g.avg_growth_per_day_30d_gb IS NULL
                          OR g.avg_growth_per_day_30d_gb <= 0
                            THEN NULL
                        ELSE g.available_space_gb / NULLIF(g.avg_growth_per_day_30d_gb, 0)
                    END AS DECIMAL(18,4)
                ) AS estimated_days_remaining
            FROM Growth AS g
        ),
        Risked AS
        (
            SELECT
                s.*,
                CASE
                    WHEN s.estimated_days_remaining <= @criticalDaysRemaining OR s.avg_growth_per_day_30d_gb >= @criticalGrowthPerDayGb THEN 'Critical'
                    WHEN s.estimated_days_remaining <= @highDaysRemaining OR s.avg_growth_per_day_30d_gb >= @highGrowthPerDayGb THEN 'High'
                    WHEN s.estimated_days_remaining <= @mediumDaysRemaining OR s.avg_growth_per_day_30d_gb >= @mediumGrowthPerDayGb THEN 'Medium'
                    WHEN s.estimated_days_remaining <= @lowDaysRemaining OR s.avg_growth_per_day_30d_gb >= @lowGrowthPerDayGb THEN 'Low'
                    ELSE 'Healthy'
                END AS risk_level
            FROM Scored AS s
        )
        INSERT INTO dbo.CapacityForecastResult
        (
            calculation_time,
            server_name,
            database_name,
            current_size_gb,
            growth_7d_gb,
            growth_30d_gb,
            growth_90d_gb,
            avg_growth_per_day_7d_gb,
            avg_growth_per_day_30d_gb,
            avg_growth_per_day_90d_gb,
            available_space_gb,
            estimated_days_remaining,
            limiting_volume_mount_point,
            shared_volume_growth_per_day_30d_gb,
            forecast_method,
            risk_level,
            recommendation
        )
        SELECT
            SYSUTCDATETIME(),
            r.server_name,
            r.database_name,
            r.current_size_gb,
            r.growth_7d_gb,
            r.growth_30d_gb,
            r.growth_90d_gb,
            r.avg_growth_per_day_7d_gb,
            r.avg_growth_per_day_30d_gb,
            r.avg_growth_per_day_90d_gb,
            r.available_space_gb,
            r.estimated_days_remaining,
            r.limiting_volume_mount_point,
            r.shared_volume_growth_per_day_30d_gb,
            r.forecast_method,
            r.risk_level,
            CASE r.risk_level
                WHEN 'Critical' THEN
                    CASE
                        WHEN r.forecast_method = 'SharedDriveGrowth'
                            THEN CONCAT(N'Immediate action required. The limiting volume ', r.limiting_volume_mount_point, N' may be exhausted soon based on total growth from databases sharing that drive.')
                        ELSE N'Immediate action required. Storage may be exhausted soon or growth is unusually high.'
                    END
                WHEN 'High' THEN
                    CASE
                        WHEN r.forecast_method = 'SharedDriveGrowth'
                            THEN CONCAT(N'Plan storage increase or growth reduction for shared volume ', r.limiting_volume_mount_point, N'.')
                        ELSE N'Plan storage increase or investigate top growing tables.'
                    END
                WHEN 'Medium' THEN N'Monitor closely and review growth trend.'
                WHEN 'Low' THEN N'No immediate action required, but continue monitoring.'
                ELSE N'Healthy growth pattern.'
            END AS recommendation
        FROM Risked AS r;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
