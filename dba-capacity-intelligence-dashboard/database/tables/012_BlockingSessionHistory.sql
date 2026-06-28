USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.BlockingSessionHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BlockingSessionHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BlockingSessionHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_BlockingSessionHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        lead_blocker_session_id INT NOT NULL,
        lead_blocker_login_name NVARCHAR(256) NULL,
        lead_blocker_host_name NVARCHAR(256) NULL,
        lead_blocker_program_name NVARCHAR(512) NULL,
        lead_blocker_status NVARCHAR(60) NULL,
        lead_blocker_command NVARCHAR(120) NULL,
        lead_blocker_running_since DATETIME2(7) NULL,
        lead_blocker_duration_minutes DECIMAL(18,2) NULL,
        lead_blocker_transaction_begin_time DATETIME2(7) NULL,
        lead_blocker_wait_type NVARCHAR(120) NULL,
        lead_blocker_sql_text NVARCHAR(MAX) NULL,
        blocked_session_id INT NOT NULL,
        blocked_login_name NVARCHAR(256) NULL,
        blocked_host_name NVARCHAR(256) NULL,
        blocked_program_name NVARCHAR(512) NULL,
        blocked_status NVARCHAR(60) NULL,
        blocked_command NVARCHAR(120) NULL,
        blocked_start_time DATETIME2(7) NULL,
        blocked_wait_type NVARCHAR(120) NULL,
        blocked_wait_duration_ms BIGINT NULL,
        blocked_wait_resource NVARCHAR(512) NULL,
        blocked_object_name NVARCHAR(512) NULL,
        blocked_lock_mode NVARCHAR(60) NULL,
        blocked_sql_text NVARCHAR(MAX) NULL,
        blocker_locks_json NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_BlockingSessionHistory_Server_Blocker_Time
        ON dbo.BlockingSessionHistory (server_name, lead_blocker_session_id, collection_time DESC)
        INCLUDE (database_name, blocked_session_id, blocked_wait_duration_ms, blocked_object_name);
END;
GO
