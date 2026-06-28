USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertLongRunningTransactionHistory
    @server_name SYSNAME,
    @database_name SYSNAME = NULL,
    @session_id INT = NULL,
    @transaction_id BIGINT = NULL,
    @transaction_begin_time DATETIME2(7) = NULL,
    @duration_minutes DECIMAL(18,2) = NULL,
    @login_name NVARCHAR(256) = NULL,
    @host_name NVARCHAR(256) = NULL,
    @program_name NVARCHAR(512) = NULL,
    @transaction_name NVARCHAR(256) = NULL,
    @transaction_type_desc NVARCHAR(60) = NULL,
    @transaction_state_desc NVARCHAR(60) = NULL,
    @command NVARCHAR(120) = NULL,
    @wait_type NVARCHAR(120) = NULL,
    @blocking_session_id INT = NULL,
    @sql_text NVARCHAR(MAX) = NULL,
    @query_plan_xml NVARCHAR(MAX) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.LongRunningTransactionHistory
        (
            collection_time,
            server_name,
            database_name,
            session_id,
            transaction_id,
            transaction_begin_time,
            duration_minutes,
            login_name,
            host_name,
            program_name,
            transaction_name,
            transaction_type_desc,
            transaction_state_desc,
            command,
            wait_type,
            blocking_session_id,
            sql_text,
            query_plan_xml
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @database_name,
            @session_id,
            @transaction_id,
            @transaction_begin_time,
            @duration_minutes,
            @login_name,
            @host_name,
            @program_name,
            @transaction_name,
            @transaction_type_desc,
            @transaction_state_desc,
            @command,
            @wait_type,
            @blocking_session_id,
            @sql_text,
            @query_plan_xml
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
