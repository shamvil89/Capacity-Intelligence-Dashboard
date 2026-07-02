USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AlertWorkNote', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertWorkNote
    (
        note_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlertWorkNote PRIMARY KEY,
        alert_id BIGINT NOT NULL,
        request_id UNIQUEIDENTIFIER NULL,
        note_time DATETIME2(7) NOT NULL CONSTRAINT DF_AlertWorkNote_note_time DEFAULT (SYSUTCDATETIME()),
        note_type NVARCHAR(60) NOT NULL,
        note_source NVARCHAR(80) NOT NULL,
        created_by NVARCHAR(256) NOT NULL CONSTRAINT DF_AlertWorkNote_created_by DEFAULT (N'System'),
        note_text NVARCHAR(MAX) NOT NULL,
        details_json NVARCHAR(MAX) NULL,
        CONSTRAINT FK_AlertWorkNote_AlertHistory FOREIGN KEY (alert_id)
            REFERENCES dbo.AlertHistory (alert_id)
            ON DELETE CASCADE,
        CONSTRAINT FK_AlertWorkNote_AutoHealRequest FOREIGN KEY (request_id)
            REFERENCES dbo.AutoHealRequest (request_id)
            ON DELETE SET NULL
    );

    CREATE INDEX IX_AlertWorkNote_Alert
        ON dbo.AlertWorkNote (alert_id, note_time DESC, note_id DESC)
        INCLUDE (note_type, note_source, created_by, request_id);

    CREATE INDEX IX_AlertWorkNote_Request
        ON dbo.AlertWorkNote (request_id, note_time DESC)
        WHERE request_id IS NOT NULL;
END;
GO
