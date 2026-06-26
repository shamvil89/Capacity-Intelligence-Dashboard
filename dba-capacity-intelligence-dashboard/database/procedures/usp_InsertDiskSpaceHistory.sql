USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertDiskSpaceHistory
    @server_name SYSNAME,
    @volume_mount_point NVARCHAR(512),
    @logical_volume_name NVARCHAR(512) = NULL,
    @total_gb DECIMAL(18,2),
    @available_gb DECIMAL(18,2),
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.DiskSpaceHistory
        (
            collection_time,
            server_name,
            volume_mount_point,
            logical_volume_name,
            total_gb,
            available_gb
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @volume_mount_point,
            @logical_volume_name,
            @total_gb,
            @available_gb
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
