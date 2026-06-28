USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertReplicationHealthHistory
    @server_name SYSNAME,
    @database_name SYSNAME = NULL,
    @publication NVARCHAR(256) = NULL,
    @agent_type NVARCHAR(80) = NULL,
    @agent_name NVARCHAR(256) = NULL,
    @subscriber_name NVARCHAR(256) = NULL,
    @subscriber_database_name SYSNAME = NULL,
    @run_status INT = NULL,
    @run_status_desc NVARCHAR(60) = NULL,
    @last_event_time DATETIME2(7) = NULL,
    @latency_seconds BIGINT = NULL,
    @delivered_commands BIGINT = NULL,
    @delivery_rate DECIMAL(18,2) = NULL,
    @error_id INT = NULL,
    @error_code INT = NULL,
    @error_text NVARCHAR(MAX) = NULL,
    @comments NVARCHAR(MAX) = NULL,
    @is_published BIT = NULL,
    @is_subscribed BIT = NULL,
    @is_merge_published BIT = NULL,
    @is_distributor BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ReplicationHealthHistory
    (
        server_name,
        database_name,
        publication,
        agent_type,
        agent_name,
        subscriber_name,
        subscriber_database_name,
        run_status,
        run_status_desc,
        last_event_time,
        latency_seconds,
        delivered_commands,
        delivery_rate,
        error_id,
        error_code,
        error_text,
        comments,
        is_published,
        is_subscribed,
        is_merge_published,
        is_distributor
    )
    VALUES
    (
        @server_name,
        @database_name,
        @publication,
        @agent_type,
        @agent_name,
        @subscriber_name,
        @subscriber_database_name,
        @run_status,
        @run_status_desc,
        @last_event_time,
        @latency_seconds,
        @delivered_commands,
        @delivery_rate,
        @error_id,
        @error_code,
        @error_text,
        @comments,
        @is_published,
        @is_subscribed,
        @is_merge_published,
        @is_distributor
    );
END;
GO
