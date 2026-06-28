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
    f.risk_level,
    f.recommendation,
    f.calculation_time
FROM RankedForecast AS f
LEFT JOIN dbo.ServerInventory AS si
    ON si.server_name = f.server_name
WHERE f.rn = 1;
GO
