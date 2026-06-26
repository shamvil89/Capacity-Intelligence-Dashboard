USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AlertHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertHistory
    (
        alert_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlertHistory PRIMARY KEY,
        alert_time DATETIME2(7) NOT NULL CONSTRAINT DF_AlertHistory_alert_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        database_name SYSNAME NULL,
        alert_type VARCHAR(100) NOT NULL,
        severity VARCHAR(20) NOT NULL,
        message NVARCHAR(2000) NOT NULL,
        is_resolved BIT NOT NULL CONSTRAINT DF_AlertHistory_is_resolved DEFAULT (0),
        resolved_at DATETIME2(7) NULL
    );

    CREATE INDEX IX_AlertHistory_Active
        ON dbo.AlertHistory (is_resolved, severity, alert_time DESC)
        INCLUDE (server_name, database_name, alert_type);
END;
GO
