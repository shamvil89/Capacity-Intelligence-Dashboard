USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.ReplicationHealthHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ReplicationHealthHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReplicationHealthHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_ReplicationHealthHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        publication NVARCHAR(256) NULL,
        agent_type NVARCHAR(80) NULL,
        agent_name NVARCHAR(256) NULL,
        subscriber_name NVARCHAR(256) NULL,
        subscriber_database_name SYSNAME NULL,
        run_status INT NULL,
        run_status_desc NVARCHAR(60) NULL,
        last_event_time DATETIME2(7) NULL,
        latency_seconds BIGINT NULL,
        delivered_commands BIGINT NULL,
        delivery_rate DECIMAL(18,2) NULL,
        error_id INT NULL,
        error_code INT NULL,
        error_text NVARCHAR(MAX) NULL,
        comments NVARCHAR(MAX) NULL,
        is_published BIT NULL,
        is_subscribed BIT NULL,
        is_merge_published BIT NULL,
        is_distributor BIT NULL
    );

    CREATE INDEX IX_ReplicationHealthHistory_Server_Time
        ON dbo.ReplicationHealthHistory (server_name, database_name, collection_time DESC)
        INCLUDE (agent_type, agent_name, run_status_desc);
END;
GO
