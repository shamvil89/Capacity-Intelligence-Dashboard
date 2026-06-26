USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.BackupSizeHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupSizeHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BackupSizeHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_BackupSizeHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NOT NULL,
        backup_start_date DATETIME NULL,
        backup_finish_date DATETIME NULL,
        backup_type VARCHAR(20) NULL,
        backup_size_gb DECIMAL(18,2) NULL,
        compressed_backup_size_gb DECIMAL(18,2) NULL,
        physical_device_name NVARCHAR(4000) NULL
    );

    CREATE INDEX IX_BackupSizeHistory_Server_Database_Finish
        ON dbo.BackupSizeHistory (server_name, database_name, backup_finish_date DESC);
END;
GO
