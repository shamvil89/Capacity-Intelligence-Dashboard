USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_LatestCapacityDashboard
AS
WITH RankedForecast AS
(
    SELECT
        f.server_name,
        f.database_name,
        f.current_size_gb,
        f.growth_7d_gb,
        f.growth_30d_gb,
        f.growth_90d_gb,
        f.avg_growth_per_day_30d_gb,
        f.available_space_gb,
        f.estimated_days_remaining,
        f.limiting_volume_mount_point,
        f.shared_volume_growth_per_day_30d_gb,
        f.forecast_method,
        f.risk_level,
        f.recommendation,
        f.calculation_time,
        ROW_NUMBER() OVER
        (
            PARTITION BY f.server_name, f.database_name
            ORDER BY f.calculation_time DESC, f.id DESC
        ) AS rn
    FROM dbo.CapacityForecastResult AS f
)
SELECT
    f.server_name,
    si.environment,
    f.database_name,
    f.current_size_gb,
    f.growth_7d_gb,
    f.growth_30d_gb,
    f.growth_90d_gb,
    f.avg_growth_per_day_30d_gb,
    f.available_space_gb,
    f.estimated_days_remaining,
    f.limiting_volume_mount_point,
    f.shared_volume_growth_per_day_30d_gb,
    f.forecast_method,
    f.risk_level,
    f.recommendation,
    f.calculation_time
FROM RankedForecast AS f
OUTER APPLY
(
    SELECT TOP (1)
        si.environment
    FROM dbo.ServerInventory AS si
    WHERE si.server_name = f.server_name
       OR
       (
           CHARINDEX(N'.', si.server_name) > 0
           AND LEFT(si.server_name, CHARINDEX(N'.', si.server_name) - 1) = f.server_name
       )
    ORDER BY CASE WHEN si.server_name = f.server_name THEN 0 ELSE 1 END
) AS si
WHERE f.rn = 1;
GO
