USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_DatabaseSizeTrend
AS
SELECT
    collection_time,
    server_name,
    database_name,
    CAST(total_size_mb / 1024.0 AS DECIMAL(18,2)) AS total_size_gb,
    CAST(data_size_mb / 1024.0 AS DECIMAL(18,2)) AS data_size_gb,
    CAST(log_size_mb / 1024.0 AS DECIMAL(18,2)) AS log_size_gb
FROM dbo.DatabaseSizeHistory;
GO
