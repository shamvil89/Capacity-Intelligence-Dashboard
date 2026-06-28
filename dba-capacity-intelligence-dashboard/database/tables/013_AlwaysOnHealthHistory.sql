USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AlwaysOnHealthHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlwaysOnHealthHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlwaysOnHealthHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_AlwaysOnHealthHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        availability_group_name SYSNAME NULL,
        replica_server_name SYSNAME NULL,
        database_name SYSNAME NULL,
        role_desc NVARCHAR(60) NULL,
        operational_state_desc NVARCHAR(60) NULL,
        connected_state_desc NVARCHAR(60) NULL,
        replica_synchronization_health_desc NVARCHAR(60) NULL,
        database_synchronization_state_desc NVARCHAR(60) NULL,
        database_synchronization_health_desc NVARCHAR(60) NULL,
        database_state_desc NVARCHAR(60) NULL,
        is_suspended BIT NULL,
        suspend_reason_desc NVARCHAR(120) NULL,
        log_send_queue_size_kb BIGINT NULL,
        redo_queue_size_kb BIGINT NULL,
        log_send_rate_kb_per_sec BIGINT NULL,
        redo_rate_kb_per_sec BIGINT NULL,
        last_sent_time DATETIME2(7) NULL,
        last_received_time DATETIME2(7) NULL,
        last_hardened_time DATETIME2(7) NULL,
        last_redone_time DATETIME2(7) NULL,
        last_commit_time DATETIME2(7) NULL,
        last_connect_error_number INT NULL,
        last_connect_error_description NVARCHAR(4000) NULL,
        last_connect_error_timestamp DATETIME2(7) NULL
    );

    CREATE INDEX IX_AlwaysOnHealthHistory_Server_Group_Time
        ON dbo.AlwaysOnHealthHistory (server_name, availability_group_name, collection_time DESC)
        INCLUDE (replica_server_name, database_name, connected_state_desc, database_synchronization_health_desc);
END;
GO
