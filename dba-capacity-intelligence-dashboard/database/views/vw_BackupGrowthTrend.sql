USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_BackupGrowthTrend
AS
SELECT
    collection_time,
    server_name,
    database_name,
    backup_start_date,
    backup_finish_date,
    backup_type,
    backup_size_gb,
    compressed_backup_size_gb,
    physical_device_name
FROM dbo.BackupSizeHistory;
GO
