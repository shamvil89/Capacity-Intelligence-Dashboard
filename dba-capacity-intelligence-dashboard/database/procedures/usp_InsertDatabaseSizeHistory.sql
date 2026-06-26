USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertDatabaseSizeHistory
    @server_name SYSNAME,
    @database_name SYSNAME,
    @total_size_mb DECIMAL(18,2),
    @data_size_mb DECIMAL(18,2) = NULL,
    @log_size_mb DECIMAL(18,2) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.DatabaseSizeHistory
        (
            collection_time,
            server_name,
            database_name,
            total_size_mb,
            data_size_mb,
            log_size_mb
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @database_name,
            @total_size_mb,
            @data_size_mb,
            @log_size_mb
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
