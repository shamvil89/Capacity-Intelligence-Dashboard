USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.TempDBUsageHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TempDBUsageHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TempDBUsageHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_TempDBUsageHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        tempdb_size_mb DECIMAL(18,2) NULL,
        user_objects_mb DECIMAL(18,2) NULL,
        internal_objects_mb DECIMAL(18,2) NULL,
        version_store_mb DECIMAL(18,2) NULL,
        free_space_mb DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_TempDBUsageHistory_Server_Time
        ON dbo.TempDBUsageHistory (server_name, collection_time DESC);
END;
GO
