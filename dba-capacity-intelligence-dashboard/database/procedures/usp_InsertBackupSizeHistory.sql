USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_InsertBackupSizeHistory
    @server_name SYSNAME,
    @database_name SYSNAME,
    @backup_start_date DATETIME = NULL,
    @backup_finish_date DATETIME = NULL,
    @backup_type VARCHAR(20) = NULL,
    @backup_size_gb DECIMAL(18,2) = NULL,
    @compressed_backup_size_gb DECIMAL(18,2) = NULL,
    @physical_device_name NVARCHAR(4000) = NULL,
    @collection_time DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO dbo.BackupSizeHistory
        (
            collection_time,
            server_name,
            database_name,
            backup_start_date,
            backup_finish_date,
            backup_type,
            backup_size_gb,
            compressed_backup_size_gb,
            physical_device_name
        )
        VALUES
        (
            COALESCE(@collection_time, SYSUTCDATETIME()),
            @server_name,
            @database_name,
            @backup_start_date,
            @backup_finish_date,
            @backup_type,
            @backup_size_gb,
            @compressed_backup_size_gb,
            @physical_device_name
        );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
