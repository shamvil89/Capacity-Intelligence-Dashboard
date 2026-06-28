USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.TempDBSessionUsageHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TempDBSessionUsageHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TempDBSessionUsageHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_TempDBSessionUsageHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        session_id INT NOT NULL,
        request_id INT NULL,
        database_name SYSNAME NULL,
        login_name NVARCHAR(256) NULL,
        host_name NVARCHAR(256) NULL,
        program_name NVARCHAR(512) NULL,
        status NVARCHAR(60) NULL,
        command NVARCHAR(120) NULL,
        wait_type NVARCHAR(120) NULL,
        blocking_session_id INT NULL,
        user_objects_mb DECIMAL(18,2) NULL,
        internal_objects_mb DECIMAL(18,2) NULL,
        total_allocated_mb DECIMAL(18,2) NULL,
        sql_text NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_TempDBSessionUsageHistory_Server_Time
        ON dbo.TempDBSessionUsageHistory (server_name, collection_time DESC)
        INCLUDE (session_id, total_allocated_mb);
END;
GO
