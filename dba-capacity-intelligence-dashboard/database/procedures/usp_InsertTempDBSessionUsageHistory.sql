USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertTempDBSessionUsageHistory
    @server_name SYSNAME,
    @session_id INT,
    @request_id INT = NULL,
    @database_name SYSNAME = NULL,
    @login_name NVARCHAR(256) = NULL,
    @host_name NVARCHAR(256) = NULL,
    @program_name NVARCHAR(512) = NULL,
    @status NVARCHAR(60) = NULL,
    @command NVARCHAR(120) = NULL,
    @wait_type NVARCHAR(120) = NULL,
    @blocking_session_id INT = NULL,
    @user_objects_mb DECIMAL(18,2) = NULL,
    @internal_objects_mb DECIMAL(18,2) = NULL,
    @total_allocated_mb DECIMAL(18,2) = NULL,
    @sql_text NVARCHAR(MAX) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.TempDBSessionUsageHistory
        (
            collection_time,
            server_name,
            session_id,
            request_id,
            database_name,
            login_name,
            host_name,
            program_name,
            status,
            command,
            wait_type,
            blocking_session_id,
            user_objects_mb,
            internal_objects_mb,
            total_allocated_mb,
            sql_text
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @session_id,
            @request_id,
            @database_name,
            @login_name,
            @host_name,
            @program_name,
            @status,
            @command,
            @wait_type,
            @blocking_session_id,
            @user_objects_mb,
            @internal_objects_mb,
            @total_allocated_mb,
            @sql_text
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
