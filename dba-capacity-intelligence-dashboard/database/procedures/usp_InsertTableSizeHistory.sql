USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertTableSizeHistory
    @server_name SYSNAME,
    @database_name SYSNAME,
    @schema_name SYSNAME,
    @table_name SYSNAME,
    @row_count BIGINT = NULL,
    @total_mb DECIMAL(18,2) = NULL,
    @used_mb DECIMAL(18,2) = NULL,
    @data_mb DECIMAL(18,2) = NULL,
    @index_mb DECIMAL(18,2) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.TableSizeHistory
        (
            collection_time,
            server_name,
            database_name,
            schema_name,
            table_name,
            row_count,
            total_mb,
            used_mb,
            data_mb,
            index_mb
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @database_name,
            @schema_name,
            @table_name,
            @row_count,
            @total_mb,
            @used_mb,
            @data_mb,
            @index_mb
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
