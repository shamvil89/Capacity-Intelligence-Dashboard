USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.TableSizeHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TableSizeHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TableSizeHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_TableSizeHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NOT NULL,
        schema_name SYSNAME NOT NULL,
        table_name SYSNAME NOT NULL,
        row_count BIGINT NULL,
        total_mb DECIMAL(18,2) NULL,
        used_mb DECIMAL(18,2) NULL,
        data_mb DECIMAL(18,2) NULL,
        index_mb DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_TableSizeHistory_Server_Database_Table_Time
        ON dbo.TableSizeHistory (server_name, database_name, schema_name, table_name, collection_time DESC);
END;
GO
