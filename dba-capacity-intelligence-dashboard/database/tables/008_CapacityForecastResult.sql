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
        estimated_days_remaining INT NULL,
        risk_level VARCHAR(20) NOT NULL,
        recommendation NVARCHAR(1000) NULL,
        CONSTRAINT CK_CapacityForecastResult_risk_level CHECK (risk_level IN ('Healthy', 'Low', 'Medium', 'High', 'Critical'))
    );

    CREATE INDEX IX_CapacityForecastResult_Server_Database_Time
        ON dbo.CapacityForecastResult (server_name, database_name, calculation_time DESC);
END;
GO
