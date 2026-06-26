USE [DBAUtility];
GO

CREATE OR ALTER PROCEDURE dbo.usp_GenerateAlerts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATETIME2(7) = CONVERT(DATE, SYSUTCDATETIME());
    DECLARE @tomorrow DATETIME2(7) = DATEADD(DAY, 1, @today);

    BEGIN TRY
        ;WITH RankedForecast AS
        (
            SELECT
                f.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY f.server_name, f.database_name
                    ORDER BY f.calculation_time DESC, f.id DESC
                ) AS rn
            FROM dbo.CapacityForecastResult AS f
        ),
        LatestForecast AS
        (
            SELECT *
            FROM RankedForecast
            WHERE rn = 1
        )
        INSERT INTO dbo.AlertHistory (server_name, database_name, alert_type, severity, message)
        SELECT
            f.server_name,
            f.database_name,
            'CapacityRisk',
            f.risk_level,
            CONCAT(f.database_name, ' is ', f.risk_level, '. ', f.recommendation)
        FROM LatestForecast AS f
        WHERE f.risk_level IN ('Critical', 'High')
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.AlertHistory AS a
              WHERE a.alert_time >= @today
                AND a.alert_time < @tomorrow
                AND a.server_name = f.server_name
                AND ISNULL(a.database_name, N'') = ISNULL(f.database_name, N'')
                AND a.alert_type = 'CapacityRisk'
          );

        ;WITH DailyLog AS
        (
            SELECT
                CONVERT(DATE, collection_time) AS capture_date,
                server_name,
                database_name,
                SUM(file_size_mb) / 1024.0 AS log_size_gb
            FROM dbo.FileSizeHistory
            WHERE file_type = 'LOG'
            GROUP BY CONVERT(DATE, collection_time), server_name, database_name
        ),
        RankedLog AS
        (
            SELECT
                d.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY d.server_name, d.database_name
                    ORDER BY d.capture_date DESC
                ) AS rn
            FROM DailyLog AS d
        ),
        LogGrowth AS
        (
            SELECT
                l.server_name,
                l.database_name,
                l.log_size_gb AS current_log_size_gb,
                p.log_size_gb AS previous_log_size_gb,
                l.log_size_gb - p.log_size_gb AS growth_gb
            FROM RankedLog AS l
            OUTER APPLY
            (
                SELECT TOP (1) d.log_size_gb
                FROM DailyLog AS d
                WHERE d.server_name = l.server_name
                  AND d.database_name = l.database_name
                  AND d.capture_date <= DATEADD(DAY, -7, l.capture_date)
                ORDER BY d.capture_date DESC
            ) AS p
            WHERE l.rn = 1
        )
        INSERT INTO dbo.AlertHistory (server_name, database_name, alert_type, severity, message)
        SELECT
            lg.server_name,
            lg.database_name,
            'LogGrowth',
            'High',
            CONCAT('Log file size increased by ', CONVERT(DECIMAL(18,2), lg.growth_gb), ' GB over the last observed 7-day window.')
        FROM LogGrowth AS lg
        WHERE lg.previous_log_size_gb IS NOT NULL
          AND lg.growth_gb >= 10
          AND lg.growth_gb >= lg.previous_log_size_gb * 0.50
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.AlertHistory AS a
              WHERE a.alert_time >= @today
                AND a.alert_time < @tomorrow
                AND a.server_name = lg.server_name
                AND ISNULL(a.database_name, N'') = ISNULL(lg.database_name, N'')
                AND a.alert_type = 'LogGrowth'
          );

        ;WITH LatestTempDb AS
        (
            SELECT
                t.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY t.server_name
                    ORDER BY t.collection_time DESC, t.id DESC
                ) AS rn
            FROM dbo.TempDBUsageHistory AS t
        )
        INSERT INTO dbo.AlertHistory (server_name, database_name, alert_type, severity, message)
        SELECT
            t.server_name,
            'tempdb',
            'TempDBUsage',
            'High',
            CONCAT('TempDB usage is ', CONVERT(DECIMAL(18,2), ((t.tempdb_size_mb - t.free_space_mb) * 100.0 / NULLIF(t.tempdb_size_mb, 0))), ' percent.')
        FROM LatestTempDb AS t
        WHERE t.rn = 1
          AND t.tempdb_size_mb > 0
          AND ((t.tempdb_size_mb - ISNULL(t.free_space_mb, 0)) * 100.0 / t.tempdb_size_mb) >= 80
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.AlertHistory AS a
              WHERE a.alert_time >= @today
                AND a.alert_time < @tomorrow
                AND a.server_name = t.server_name
                AND ISNULL(a.database_name, N'') = N'tempdb'
                AND a.alert_type = 'TempDBUsage'
          );

        ;WITH LatestDisk AS
        (
            SELECT
                d.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY d.server_name, d.volume_mount_point
                    ORDER BY d.collection_time DESC, d.id DESC
                ) AS rn
            FROM dbo.DiskSpaceHistory AS d
        )
        INSERT INTO dbo.AlertHistory (server_name, database_name, alert_type, severity, message)
        SELECT
            d.server_name,
            NULL,
            'DiskSpaceLow',
            CASE WHEN d.available_gb <= 10 OR d.used_percent >= 95 THEN 'Critical' ELSE 'High' END,
            CONCAT('Volume ', d.volume_mount_point, ' has ', d.available_gb, ' GB available and is ', d.used_percent, ' percent used.')
        FROM LatestDisk AS d
        WHERE d.rn = 1
          AND (d.available_gb <= 20 OR d.used_percent >= 90)
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.AlertHistory AS a
              WHERE a.alert_time >= @today
                AND a.alert_time < @tomorrow
                AND a.server_name = d.server_name
                AND a.alert_type = 'DiskSpaceLow'
                AND a.message LIKE CONCAT('Volume ', d.volume_mount_point, '%')
          );

        ;WITH RankedBackup AS
        (
            SELECT
                b.*,
                ROW_NUMBER() OVER
                (
                    PARTITION BY b.server_name, b.database_name, b.backup_type
                    ORDER BY b.backup_finish_date DESC, b.id DESC
                ) AS rn
            FROM dbo.BackupSizeHistory AS b
            WHERE b.backup_finish_date IS NOT NULL
              AND b.backup_size_gb IS NOT NULL
        ),
        BackupGrowth AS
        (
            SELECT
                b.server_name,
                b.database_name,
                b.backup_type,
                b.backup_size_gb,
                p.avg_backup_size_gb
            FROM RankedBackup AS b
            OUTER APPLY
            (
                SELECT AVG(p.backup_size_gb) AS avg_backup_size_gb
                FROM dbo.BackupSizeHistory AS p
                WHERE p.server_name = b.server_name
                  AND p.database_name = b.database_name
                  AND ISNULL(p.backup_type, '') = ISNULL(b.backup_type, '')
                  AND p.backup_finish_date < b.backup_finish_date
                  AND p.backup_finish_date >= DATEADD(DAY, -30, b.backup_finish_date)
            ) AS p
            WHERE b.rn = 1
        )
        INSERT INTO dbo.AlertHistory (server_name, database_name, alert_type, severity, message)
        SELECT
            bg.server_name,
            bg.database_name,
            'BackupGrowth',
            'Medium',
            CONCAT(bg.backup_type, ' backup size increased sharply. Latest: ', bg.backup_size_gb, ' GB, 30-day average: ', CONVERT(DECIMAL(18,2), bg.avg_backup_size_gb), ' GB.')
        FROM BackupGrowth AS bg
        WHERE bg.avg_backup_size_gb IS NOT NULL
          AND bg.backup_size_gb >= bg.avg_backup_size_gb * 1.5
          AND bg.backup_size_gb - bg.avg_backup_size_gb >= 5
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.AlertHistory AS a
              WHERE a.alert_time >= @today
                AND a.alert_time < @tomorrow
                AND a.server_name = bg.server_name
                AND ISNULL(a.database_name, N'') = ISNULL(bg.database_name, N'')
                AND a.alert_type = 'BackupGrowth'
          );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
