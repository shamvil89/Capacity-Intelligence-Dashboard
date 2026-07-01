USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.CapacityForecastResult', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CapacityForecastResult
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CapacityForecastResult PRIMARY KEY,
        calculation_time DATETIME2(7) NOT NULL CONSTRAINT DF_CapacityForecastResult_calculation_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NOT NULL,
        current_size_gb DECIMAL(18,2) NOT NULL,
        growth_7d_gb DECIMAL(18,2) NULL,
        growth_30d_gb DECIMAL(18,2) NULL,
        growth_90d_gb DECIMAL(18,2) NULL,
        avg_growth_per_day_7d_gb DECIMAL(18,2) NULL,
        avg_growth_per_day_30d_gb DECIMAL(18,2) NULL,
        avg_growth_per_day_90d_gb DECIMAL(18,2) NULL,
        available_space_gb DECIMAL(18,2) NULL,
        estimated_days_remaining DECIMAL(18,4) NULL,
        limiting_volume_mount_point NVARCHAR(512) NULL,
        shared_volume_growth_per_day_30d_gb DECIMAL(18,4) NULL,
        forecast_method VARCHAR(40) NULL,
        risk_level VARCHAR(20) NOT NULL,
        recommendation NVARCHAR(1000) NULL,
        CONSTRAINT CK_CapacityForecastResult_risk_level CHECK (risk_level IN ('Healthy', 'Low', 'Medium', 'High', 'Critical'))
    );

    CREATE INDEX IX_CapacityForecastResult_Server_Database_Time
        ON dbo.CapacityForecastResult (server_name, database_name, calculation_time DESC);
END;
GO

IF COL_LENGTH(N'dbo.CapacityForecastResult', N'estimated_days_remaining') IS NOT NULL
BEGIN
    ALTER TABLE dbo.CapacityForecastResult
        ALTER COLUMN estimated_days_remaining DECIMAL(18,4) NULL;
END;
GO

IF COL_LENGTH(N'dbo.CapacityForecastResult', N'limiting_volume_mount_point') IS NULL
BEGIN
    ALTER TABLE dbo.CapacityForecastResult
        ADD limiting_volume_mount_point NVARCHAR(512) NULL;
END;
GO

IF COL_LENGTH(N'dbo.CapacityForecastResult', N'shared_volume_growth_per_day_30d_gb') IS NULL
BEGIN
    ALTER TABLE dbo.CapacityForecastResult
        ADD shared_volume_growth_per_day_30d_gb DECIMAL(18,4) NULL;
END;
GO

IF COL_LENGTH(N'dbo.CapacityForecastResult', N'forecast_method') IS NULL
BEGIN
    ALTER TABLE dbo.CapacityForecastResult
        ADD forecast_method VARCHAR(40) NULL;
END;
GO
