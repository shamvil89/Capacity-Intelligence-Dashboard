USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AlertHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertHistory
    (
        alert_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlertHistory PRIMARY KEY,
        alert_time DATETIME2(7) NOT NULL CONSTRAINT DF_AlertHistory_alert_time DEFAULT (SYSUTCDATETIME()),
        alert_key NVARCHAR(512) NULL,
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        alert_type VARCHAR(100) NOT NULL,
        severity VARCHAR(20) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        source_script NVARCHAR(260) NULL,
        details_json NVARCHAR(MAX) NULL,
        is_resolved BIT NOT NULL CONSTRAINT DF_AlertHistory_is_resolved DEFAULT (0),
        resolved_at DATETIME2(7) NULL
    );

    CREATE INDEX IX_AlertHistory_Active
        ON dbo.AlertHistory (is_resolved, severity, alert_time DESC)
        INCLUDE (server_name, database_name, alert_type);
END;
GO

IF COL_LENGTH(N'dbo.AlertHistory', N'source_script') IS NULL
BEGIN
    ALTER TABLE dbo.AlertHistory
        ADD source_script NVARCHAR(260) NULL;
END;
GO

IF COL_LENGTH(N'dbo.AlertHistory', N'alert_key') IS NULL
BEGIN
    ALTER TABLE dbo.AlertHistory
        ADD alert_key NVARCHAR(512) NULL;
END;
GO

IF COL_LENGTH(N'dbo.AlertHistory', N'details_json') IS NULL
BEGIN
    ALTER TABLE dbo.AlertHistory
        ADD details_json NVARCHAR(MAX) NULL;
END;
GO

IF COL_LENGTH(N'dbo.AlertHistory', N'is_resolved') IS NULL
BEGIN
    ALTER TABLE dbo.AlertHistory
        ADD is_resolved BIT NOT NULL CONSTRAINT DF_AlertHistory_is_resolved DEFAULT (0);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.AlertHistory')
      AND name = N'IX_AlertHistory_ActiveAlertKey'
)
BEGIN
    CREATE INDEX IX_AlertHistory_ActiveAlertKey
        ON dbo.AlertHistory (is_resolved, alert_key)
        INCLUDE (server_name, database_name, alert_type, alert_time);
END;
GO

IF COL_LENGTH(N'dbo.AlertHistory', N'resolved_at') IS NULL
BEGIN
    ALTER TABLE dbo.AlertHistory
        ADD resolved_at DATETIME2(7) NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.AlertHistory')
      AND name = N'IX_AlertHistory_Active'
)
BEGIN
    CREATE INDEX IX_AlertHistory_Active
        ON dbo.AlertHistory (is_resolved, severity, alert_time DESC)
        INCLUDE (server_name, database_name, alert_type);
END;
GO
