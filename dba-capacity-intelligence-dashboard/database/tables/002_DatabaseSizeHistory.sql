USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.DatabaseSizeHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DatabaseSizeHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DatabaseSizeHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_DatabaseSizeHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NOT NULL,
        total_size_mb DECIMAL(18,2) NOT NULL,
        data_size_mb DECIMAL(18,2) NULL,
        log_size_mb DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_DatabaseSizeHistory_Server_Database_Time
        ON dbo.DatabaseSizeHistory (server_name, database_name, collection_time DESC);
END;
GO
