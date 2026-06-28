USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.LongRunningTransactionHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LongRunningTransactionHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LongRunningTransactionHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_LongRunningTransactionHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        session_id INT NULL,
        transaction_id BIGINT NULL,
        transaction_begin_time DATETIME2(7) NULL,
        duration_minutes DECIMAL(18,2) NULL,
        login_name NVARCHAR(256) NULL,
        host_name NVARCHAR(256) NULL,
        program_name NVARCHAR(512) NULL,
        transaction_name NVARCHAR(256) NULL,
        transaction_type_desc NVARCHAR(60) NULL,
        transaction_state_desc NVARCHAR(60) NULL,
        command NVARCHAR(120) NULL,
        wait_type NVARCHAR(120) NULL,
        blocking_session_id INT NULL,
        sql_text NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_LongRunningTransactionHistory_Server_Time
        ON dbo.LongRunningTransactionHistory (server_name, collection_time DESC)
        INCLUDE (database_name, session_id, duration_minutes);
END;
GO
