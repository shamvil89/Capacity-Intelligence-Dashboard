USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.FileSizeHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FileSizeHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileSizeHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_FileSizeHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NOT NULL,
        logical_file_name SYSNAME NOT NULL,
        physical_file_name NVARCHAR(4000) NULL,
        file_type VARCHAR(20) NOT NULL,
        file_size_mb DECIMAL(18,2) NOT NULL,
        used_space_mb DECIMAL(18,2) NULL,
        free_space_mb DECIMAL(18,2) NULL,
        growth_setting NVARCHAR(100) NULL,
        max_size_mb DECIMAL(18,2) NULL,
        recovery_model_desc VARCHAR(60) NULL,
        log_reuse_wait_desc NVARCHAR(120) NULL,
        volume_mount_point NVARCHAR(512) NULL,
        volume_total_gb DECIMAL(18,2) NULL,
        volume_available_gb DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_FileSizeHistory_Server_Database_Time
        ON dbo.FileSizeHistory (server_name, database_name, collection_time DESC);
END;
GO

IF COL_LENGTH(N'dbo.FileSizeHistory', N'recovery_model_desc') IS NULL
BEGIN
    ALTER TABLE dbo.FileSizeHistory
        ADD recovery_model_desc VARCHAR(60) NULL;
END;
GO

IF COL_LENGTH(N'dbo.FileSizeHistory', N'log_reuse_wait_desc') IS NULL
BEGIN
    ALTER TABLE dbo.FileSizeHistory
        ADD log_reuse_wait_desc NVARCHAR(120) NULL;
END;
GO

IF COL_LENGTH(N'dbo.FileSizeHistory', N'volume_mount_point') IS NULL
BEGIN
    ALTER TABLE dbo.FileSizeHistory
        ADD volume_mount_point NVARCHAR(512) NULL;
END;
GO

IF COL_LENGTH(N'dbo.FileSizeHistory', N'volume_total_gb') IS NULL
BEGIN
    ALTER TABLE dbo.FileSizeHistory
        ADD volume_total_gb DECIMAL(18,2) NULL;
END;
GO

IF COL_LENGTH(N'dbo.FileSizeHistory', N'volume_available_gb') IS NULL
BEGIN
    ALTER TABLE dbo.FileSizeHistory
        ADD volume_available_gb DECIMAL(18,2) NULL;
END;
GO
