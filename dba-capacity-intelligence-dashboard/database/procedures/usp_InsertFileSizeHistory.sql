USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertFileSizeHistory
    @server_name SYSNAME,
    @database_name SYSNAME,
    @logical_file_name SYSNAME,
    @physical_file_name NVARCHAR(4000) = NULL,
    @file_type VARCHAR(20),
    @file_size_mb DECIMAL(18,2),
    @used_space_mb DECIMAL(18,2) = NULL,
    @free_space_mb DECIMAL(18,2) = NULL,
    @growth_setting NVARCHAR(100) = NULL,
    @max_size_mb DECIMAL(18,2) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.FileSizeHistory
        (
            collection_time,
            server_name,
            database_name,
            logical_file_name,
            physical_file_name,
            file_type,
            file_size_mb,
            used_space_mb,
            free_space_mb,
            growth_setting,
            max_size_mb
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @database_name,
            @logical_file_name,
            @physical_file_name,
            @file_type,
            @file_size_mb,
            @used_space_mb,
            @free_space_mb,
            @growth_setting,
            @max_size_mb
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
