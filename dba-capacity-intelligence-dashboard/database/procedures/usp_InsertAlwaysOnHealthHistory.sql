USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertAlwaysOnHealthHistory
    @server_name SYSNAME,
    @availability_group_name SYSNAME = NULL,
    @replica_server_name SYSNAME = NULL,
    @database_name SYSNAME = NULL,
    @role_desc NVARCHAR(60) = NULL,
    @operational_state_desc NVARCHAR(60) = NULL,
    @connected_state_desc NVARCHAR(60) = NULL,
    @replica_synchronization_health_desc NVARCHAR(60) = NULL,
    @database_synchronization_state_desc NVARCHAR(60) = NULL,
    @database_synchronization_health_desc NVARCHAR(60) = NULL,
    @database_state_desc NVARCHAR(60) = NULL,
    @is_suspended BIT = NULL,
    @suspend_reason_desc NVARCHAR(120) = NULL,
    @log_send_queue_size_kb BIGINT = NULL,
    @redo_queue_size_kb BIGINT = NULL,
    @log_send_rate_kb_per_sec BIGINT = NULL,
    @redo_rate_kb_per_sec BIGINT = NULL,
    @last_sent_time DATETIME2(7) = NULL,
    @last_received_time DATETIME2(7) = NULL,
    @last_hardened_time DATETIME2(7) = NULL,
    @last_redone_time DATETIME2(7) = NULL,
    @last_commit_time DATETIME2(7) = NULL,
    @last_connect_error_number INT = NULL,
    @last_connect_error_description NVARCHAR(4000) = NULL,
    @last_connect_error_timestamp DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AlwaysOnHealthHistory
    (
        server_name,
        availability_group_name,
        replica_server_name,
        database_name,
        role_desc,
        operational_state_desc,
        connected_state_desc,
        replica_synchronization_health_desc,
        database_synchronization_state_desc,
        database_synchronization_health_desc,
        database_state_desc,
        is_suspended,
        suspend_reason_desc,
        log_send_queue_size_kb,
        redo_queue_size_kb,
        log_send_rate_kb_per_sec,
        redo_rate_kb_per_sec,
        last_sent_time,
        last_received_time,
        last_hardened_time,
        last_redone_time,
        last_commit_time,
        last_connect_error_number,
        last_connect_error_description,
        last_connect_error_timestamp
    )
    VALUES
    (
        @server_name,
        @availability_group_name,
        @replica_server_name,
        @database_name,
        @role_desc,
        @operational_state_desc,
        @connected_state_desc,
        @replica_synchronization_health_desc,
        @database_synchronization_state_desc,
        @database_synchronization_health_desc,
        @database_state_desc,
        @is_suspended,
        @suspend_reason_desc,
        @log_send_queue_size_kb,
        @redo_queue_size_kb,
        @log_send_rate_kb_per_sec,
        @redo_rate_kb_per_sec,
        @last_sent_time,
        @last_received_time,
        @last_hardened_time,
        @last_redone_time,
        @last_commit_time,
        @last_connect_error_number,
        @last_connect_error_description,
        @last_connect_error_timestamp
    );
END;
GO
