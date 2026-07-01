USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AutoHealRequest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AutoHealRequest
    (
        request_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_AutoHealRequest PRIMARY KEY,
        requested_at DATETIME2(7) NOT NULL CONSTRAINT DF_AutoHealRequest_requested_at DEFAULT (SYSUTCDATETIME()),
        completed_at DATETIME2(7) NULL,
        alert_id BIGINT NULL,
        alert_type VARCHAR(100) NULL,
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        action_type VARCHAR(80) NOT NULL,
        target_path NVARCHAR(4000) NULL,
        retention_days INT NULL,
        status VARCHAR(40) NOT NULL CONSTRAINT DF_AutoHealRequest_status DEFAULT ('Queued'),
        pipeline_run_id INT NULL,
        pipeline_web_url NVARCHAR(1000) NULL,
        message NVARCHAR(2000) NULL,
        details_json NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_AutoHealRequest_RequestedAt
        ON dbo.AutoHealRequest (requested_at DESC)
        INCLUDE (server_name, database_name, action_type, status);
END;
GO
IF OBJECT_ID(N'dbo.AutoHealFileCandidate', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AutoHealFileCandidate
    (
        candidate_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AutoHealFileCandidate PRIMARY KEY,
        request_id UNIQUEIDENTIFIER NOT NULL,
        discovered_at DATETIME2(7) NOT NULL CONSTRAINT DF_AutoHealFileCandidate_discovered_at DEFAULT (SYSUTCDATETIME()),
        file_path NVARCHAR(4000) NOT NULL,
        extension VARCHAR(10) NULL,
        size_mb DECIMAL(18,2) NULL,
        last_write_time_utc DATETIME2(7) NULL,
        age_days DECIMAL(18,2) NULL,
        is_older_than_retention BIT NOT NULL CONSTRAINT DF_AutoHealFileCandidate_is_older DEFAULT (0),
        selected_for_cleanup BIT NOT NULL CONSTRAINT DF_AutoHealFileCandidate_selected DEFAULT (0),
        action_status VARCHAR(40) NOT NULL CONSTRAINT DF_AutoHealFileCandidate_status DEFAULT ('Candidate'),
        error_message NVARCHAR(2000) NULL,
        CONSTRAINT FK_AutoHealFileCandidate_Request FOREIGN KEY (request_id)
            REFERENCES dbo.AutoHealRequest (request_id)
            ON DELETE CASCADE
    );

    CREATE INDEX IX_AutoHealFileCandidate_Request
        ON dbo.AutoHealFileCandidate (request_id, action_status)
        INCLUDE (file_path, size_mb, last_write_time_utc, age_days, is_older_than_retention);
END;
GO

IF COL_LENGTH(N'dbo.AutoHealRequest', N'pipeline_web_url') IS NULL
BEGIN
    ALTER TABLE dbo.AutoHealRequest
        ADD pipeline_web_url NVARCHAR(1000) NULL;
END;
GO

IF COL_LENGTH(N'dbo.AutoHealFileCandidate', N'selected_for_cleanup') IS NULL
BEGIN
    ALTER TABLE dbo.AutoHealFileCandidate
        ADD selected_for_cleanup BIT NOT NULL CONSTRAINT DF_AutoHealFileCandidate_selected DEFAULT (0);
END;
GO
