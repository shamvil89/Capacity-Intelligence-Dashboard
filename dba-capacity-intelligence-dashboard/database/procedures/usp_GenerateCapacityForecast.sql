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
        Growth AS
        (
            SELECT
                c.server_name,
                c.database_name,
                CAST(c.total_size_mb / 1024.0 AS DECIMAL(18,2)) AS current_size_gb,
                CAST((c.total_size_mb - d7.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_7d_gb,
                CAST((c.total_size_mb - d30.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_30d_gb,
                CAST((c.total_size_mb - d90.total_size_mb) / 1024.0 AS DECIMAL(18,2)) AS growth_90d_gb,
                CAST((c.total_size_mb - d7.total_size_mb) / 1024.0 / 7.0 AS DECIMAL(18,2)) AS avg_growth_per_day_7d_gb,
                CAST((c.total_size_mb - d30.total_size_mb) / 1024.0 / 30.0 AS DECIMAL(18,2)) AS avg_growth_per_day_30d_gb,
                CAST((c.total_size_mb - d90.total_size_mb) / 1024.0 / 90.0 AS DECIMAL(18,2)) AS avg_growth_per_day_90d_gb,
                a.available_space_gb
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
        ),
        Scored AS
        (
            SELECT
                g.*,
                CASE
                    WHEN g.available_space_gb IS NULL
                      OR g.avg_growth_per_day_30d_gb IS NULL
                      OR g.avg_growth_per_day_30d_gb <= 0
                        THEN NULL
                    ELSE CONVERT(INT, FLOOR(g.available_space_gb / NULLIF(g.avg_growth_per_day_30d_gb, 0)))
                END AS estimated_days_remaining
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
            r.risk_level,
            CASE r.risk_level
                WHEN 'Critical' THEN N'Immediate action required. Storage may be exhausted soon or growth is unusually high.'
                WHEN 'High' THEN N'Plan storage increase or investigate top growing tables.'
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
