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
        max_size_mb DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_FileSizeHistory_Server_Database_Time
        ON dbo.FileSizeHistory (server_name, database_name, collection_time DESC);
END;
GO
