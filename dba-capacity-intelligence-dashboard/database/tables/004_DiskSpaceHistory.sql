USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.DiskSpaceHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DiskSpaceHistory
    (
        id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DiskSpaceHistory PRIMARY KEY,
        collection_time DATETIME2(7) NOT NULL CONSTRAINT DF_DiskSpaceHistory_collection_time DEFAULT (SYSUTCDATETIME()),
        server_name SYSNAME NOT NULL,
        volume_mount_point NVARCHAR(512) NOT NULL,
        logical_volume_name NVARCHAR(512) NULL,
        total_gb DECIMAL(18,2) NOT NULL,
        available_gb DECIMAL(18,2) NOT NULL,
        used_gb AS (total_gb - available_gb) PERSISTED,
        used_percent AS
        (
            CASE
                WHEN total_gb > 0
                    THEN CONVERT(DECIMAL(9,2), ((total_gb - available_gb) * 100.0 / total_gb))
                ELSE CONVERT(DECIMAL(9,2), 0)
            END
        ) PERSISTED
    );

    CREATE INDEX IX_DiskSpaceHistory_Server_Volume_Time
        ON dbo.DiskSpaceHistory (server_name, volume_mount_point, collection_time DESC);
END;
GO
