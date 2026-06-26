USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertTempDBUsageHistory
    @server_name SYSNAME,
    @tempdb_size_mb DECIMAL(18,2) = NULL,
    @user_objects_mb DECIMAL(18,2) = NULL,
    @internal_objects_mb DECIMAL(18,2) = NULL,
    @version_store_mb DECIMAL(18,2) = NULL,
    @free_space_mb DECIMAL(18,2) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.TempDBUsageHistory
        (
            collection_time,
            server_name,
            tempdb_size_mb,
            user_objects_mb,
            internal_objects_mb,
            version_store_mb,
            free_space_mb
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @tempdb_size_mb,
            @user_objects_mb,
            @internal_objects_mb,
            @version_store_mb,
            @free_space_mb
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
