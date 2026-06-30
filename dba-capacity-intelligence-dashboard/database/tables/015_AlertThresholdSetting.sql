USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.AlertThresholdSetting', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertThresholdSetting
    (
        setting_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlertThresholdSetting PRIMARY KEY,
        alert_type VARCHAR(100) NOT NULL,
        setting_key VARCHAR(120) NOT NULL,
        display_name NVARCHAR(180) NOT NULL,
        description NVARCHAR(1000) NULL,
        unit VARCHAR(40) NULL,
        setting_value_decimal DECIMAL(18,4) NOT NULL,
        default_value_decimal DECIMAL(18,4) NOT NULL,
        minimum_value_decimal DECIMAL(18,4) NULL,
        maximum_value_decimal DECIMAL(18,4) NULL,
        sort_order INT NOT NULL,
        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_AlertThresholdSetting_updated_at DEFAULT (SYSUTCDATETIME()),
        updated_by SYSNAME NULL,
        CONSTRAINT UQ_AlertThresholdSetting_Type_Key UNIQUE (alert_type, setting_key),
        CONSTRAINT CK_AlertThresholdSetting_Value_Min CHECK (minimum_value_decimal IS NULL OR setting_value_decimal >= minimum_value_decimal),
        CONSTRAINT CK_AlertThresholdSetting_Value_Max CHECK (maximum_value_decimal IS NULL OR setting_value_decimal <= maximum_value_decimal)
    );

    CREATE INDEX IX_AlertThresholdSetting_AlertType_Sort
        ON dbo.AlertThresholdSetting (alert_type, sort_order, setting_key);
END;
GO

DECLARE @Defaults TABLE
(
    alert_type VARCHAR(100) NOT NULL,
    setting_key VARCHAR(120) NOT NULL,
    display_name NVARCHAR(180) NOT NULL,
    description NVARCHAR(1000) NULL,
    unit VARCHAR(40) NULL,
    setting_value_decimal DECIMAL(18,4) NOT NULL,
    default_value_decimal DECIMAL(18,4) NOT NULL,
    minimum_value_decimal DECIMAL(18,4) NULL,
    maximum_value_decimal DECIMAL(18,4) NULL,
    sort_order INT NOT NULL
);

INSERT INTO @Defaults
(
    alert_type,
    setting_key,
    display_name,
    description,
    unit,
    setting_value_decimal,
    default_value_decimal,
    minimum_value_decimal,
    maximum_value_decimal,
    sort_order
)
VALUES
('CapacityRisk', 'CriticalDaysRemaining', N'Critical days remaining', N'Capacity forecast becomes Critical when estimated days remaining is at or below this value.', 'days', 7, 7, 0, NULL, 10),
('CapacityRisk', 'HighDaysRemaining', N'High days remaining', N'Capacity forecast becomes High when estimated days remaining is at or below this value.', 'days', 15, 15, 0, NULL, 20),
('CapacityRisk', 'MediumDaysRemaining', N'Medium days remaining', N'Capacity forecast becomes Medium when estimated days remaining is at or below this value.', 'days', 30, 30, 0, NULL, 30),
('CapacityRisk', 'LowDaysRemaining', N'Low days remaining', N'Capacity forecast becomes Low when estimated days remaining is at or below this value.', 'days', 60, 60, 0, NULL, 40),
('CapacityRisk', 'CriticalGrowthPerDayGb', N'Critical daily growth', N'Capacity forecast becomes Critical when average 30-day daily growth is at or above this value.', 'GB/day', 20, 20, 0, NULL, 50),
('CapacityRisk', 'HighGrowthPerDayGb', N'High daily growth', N'Capacity forecast becomes High when average 30-day daily growth is at or above this value.', 'GB/day', 10, 10, 0, NULL, 60),
('CapacityRisk', 'MediumGrowthPerDayGb', N'Medium daily growth', N'Capacity forecast becomes Medium when average 30-day daily growth is at or above this value.', 'GB/day', 5, 5, 0, NULL, 70),
('CapacityRisk', 'LowGrowthPerDayGb', N'Low daily growth', N'Capacity forecast becomes Low when average 30-day daily growth is at or above this value.', 'GB/day', 1, 1, 0, NULL, 80),

('LogFileExhaustionRisk', 'CriticalRemainingToCapGb', N'Critical remaining log headroom', N'Critical when remaining transaction log headroom is at or below this value.', 'GB', 10, 10, 0, NULL, 10),
('LogFileExhaustionRisk', 'CriticalPercentOfCap', N'Critical percent of cap', N'Critical when log file size uses this percentage of effective cap.', 'percent', 95, 95, 0, 100, 20),
('LogFileExhaustionRisk', 'CriticalProjectedHoursToCap', N'Critical projected hours to cap', N'Critical when projected time to effective cap is at or below this value.', 'hours', 24, 24, 0, NULL, 30),
('LogFileExhaustionRisk', 'AlertRemainingToCapGb', N'Alert remaining log headroom', N'Raises an alert when remaining transaction log headroom is at or below this value.', 'GB', 20, 20, 0, NULL, 40),
('LogFileExhaustionRisk', 'AlertPercentOfCap', N'Alert percent of cap', N'Raises an alert when log file size uses this percentage of effective cap.', 'percent', 85, 85, 0, 100, 50),
('LogFileExhaustionRisk', 'AlertProjectedHoursToCap', N'Alert projected hours to cap', N'Raises an alert when projected time to effective cap is at or below this value.', 'hours', 72, 72, 0, NULL, 60),
('LogFileExhaustionRisk', 'AlertGrowth24HoursGb', N'Alert 24-hour growth', N'Raises an alert when 24-hour log growth is at or above this value and remaining headroom is within the multiplier threshold.', 'GB', 10, 10, 0, NULL, 70),
('LogFileExhaustionRisk', 'AlertGrowthHeadroomMultiplier', N'Growth headroom multiplier', N'Raises an alert when remaining headroom is less than 24-hour growth multiplied by this value.', 'multiplier', 3, 3, 0, NULL, 80),
('LogFileExhaustionRisk', 'Growth24hWindowHours', N'24-hour growth window', N'Window used to calculate recent transaction log growth for exhaustion projections.', 'hours', 24, 24, 1, NULL, 90),
('LogFileExhaustionRisk', 'Growth7dWindowDays', N'7-day growth window', N'Window used to calculate longer transaction log growth for exhaustion projections.', 'days', 7, 7, 1, NULL, 100),

('UnusuallyLargeLogFile', 'AlertMinimumLogSizeGb', N'Minimum log size', N'Minimum current log size required before unusually-large-log checks can raise an alert.', 'GB', 16, 16, 0, NULL, 10),
('UnusuallyLargeLogFile', 'AlertLogToDataRatio', N'Alert log/data ratio', N'Raises an alert when current log size is this many times data size.', 'ratio', 2, 2, 0, NULL, 20),
('UnusuallyLargeLogFile', 'AlertAbsoluteLogSizeGb', N'Alert absolute log size', N'Raises an alert when current log size is at or above this value.', 'GB', 128, 128, 0, NULL, 30),
('UnusuallyLargeLogFile', 'AlertPercentOfCap', N'Alert percent of cap', N'Raises an alert when current log size uses this percentage of effective cap.', 'percent', 50, 50, 0, 100, 40),
('UnusuallyLargeLogFile', 'HighLogToDataRatio', N'High log/data ratio', N'High severity when current log size is this many times data size.', 'ratio', 4, 4, 0, NULL, 50),
('UnusuallyLargeLogFile', 'HighAbsoluteLogSizeGb', N'High absolute log size', N'High severity when current log size is at or above this value.', 'GB', 128, 128, 0, NULL, 60),
('UnusuallyLargeLogFile', 'HighPercentOfCap', N'High percent of cap', N'High severity when current log size uses this percentage of effective cap.', 'percent', 50, 50, 0, 100, 70),
('UnusuallyLargeLogFile', 'CriticalLogToDataRatio', N'Critical log/data ratio', N'Critical severity when current log size is this many times data size.', 'ratio', 8, 8, 0, NULL, 80),
('UnusuallyLargeLogFile', 'CriticalAbsoluteLogSizeGb', N'Critical absolute log size', N'Critical severity when current log size is at or above this value.', 'GB', 512, 512, 0, NULL, 90),
('UnusuallyLargeLogFile', 'CriticalPercentOfCap', N'Critical percent of cap', N'Critical severity when current log size uses this percentage of effective cap.', 'percent', 75, 75, 0, 100, 100),

('LogFileGrowthSpike', 'AlertPreviousGrowthGb', N'Alert previous-sample growth', N'Raises an alert when log growth since previous sample is at or above this value.', 'GB', 1, 1, 0, NULL, 10),
('LogFileGrowthSpike', 'AlertPreviousGrowthModerateGb', N'Alert moderate previous growth', N'Raises an alert when previous-sample growth reaches this value and percentage growth threshold is met.', 'GB', 0.25, 0.25, 0, NULL, 20),
('LogFileGrowthSpike', 'AlertPreviousGrowthModeratePercent', N'Alert moderate previous growth percent', N'Percentage growth required with moderate previous-sample growth.', 'percent', 100, 100, 0, NULL, 30),
('LogFileGrowthSpike', 'AlertPreviousGrowthSmallGb', N'Alert small previous growth', N'Raises an alert when previous-sample growth reaches this value and high percentage growth threshold is met.', 'GB', 0.0625, 0.0625, 0, NULL, 40),
('LogFileGrowthSpike', 'AlertPreviousGrowthSmallPercent', N'Alert small previous growth percent', N'Percentage growth required with small previous-sample growth.', 'percent', 500, 500, 0, NULL, 50),
('LogFileGrowthSpike', 'Baseline24hWindowHours', N'24-hour baseline window', N'Window used to find the lowest recent log size baseline.', 'hours', 24, 24, 1, NULL, 55),
('LogFileGrowthSpike', 'Alert24hGrowthGb', N'Alert 24-hour growth', N'Raises an alert when growth versus 24-hour baseline is at or above this value.', 'GB', 2, 2, 0, NULL, 60),
('LogFileGrowthSpike', 'Alert24hGrowthModerateGb', N'Alert moderate 24-hour growth', N'Raises an alert when 24-hour growth reaches this value and percentage growth threshold is met.', 'GB', 0.5, 0.5, 0, NULL, 70),
('LogFileGrowthSpike', 'Alert24hGrowthModeratePercent', N'Alert moderate 24-hour growth percent', N'Percentage growth required with moderate 24-hour growth.', 'percent', 100, 100, 0, NULL, 80),
('LogFileGrowthSpike', 'Alert24hGrowthSmallGb', N'Alert small 24-hour growth', N'Raises an alert when 24-hour growth reaches this value and high percentage growth threshold is met.', 'GB', 0.0625, 0.0625, 0, NULL, 90),
('LogFileGrowthSpike', 'Alert24hGrowthSmallPercent', N'Alert small 24-hour growth percent', N'Percentage growth required with small 24-hour growth.', 'percent', 500, 500, 0, NULL, 100),
('LogFileGrowthSpike', 'Baseline7dWindowDays', N'7-day baseline window', N'Window used to find the lowest longer-term log size baseline.', 'days', 7, 7, 1, NULL, 105),
('LogFileGrowthSpike', 'Alert7dGrowthGb', N'Alert 7-day growth', N'Raises an alert when growth versus 7-day baseline is at or above this value.', 'GB', 5, 5, 0, NULL, 110),
('LogFileGrowthSpike', 'Alert7dGrowthModerateGb', N'Alert moderate 7-day growth', N'Raises an alert when 7-day growth reaches this value and percentage growth threshold is met.', 'GB', 1, 1, 0, NULL, 120),
('LogFileGrowthSpike', 'Alert7dGrowthModeratePercent', N'Alert moderate 7-day growth percent', N'Percentage growth required with moderate 7-day growth.', 'percent', 100, 100, 0, NULL, 130),
('LogFileGrowthSpike', 'Alert7dGrowthSmallGb', N'Alert small 7-day growth', N'Raises an alert when 7-day growth reaches this value and high percentage growth threshold is met.', 'GB', 0.0625, 0.0625, 0, NULL, 140),
('LogFileGrowthSpike', 'Alert7dGrowthSmallPercent', N'Alert small 7-day growth percent', N'Percentage growth required with small 7-day growth.', 'percent', 500, 500, 0, NULL, 150),
('LogFileGrowthSpike', 'HighPreviousGrowthGb', N'High previous-sample growth', N'High severity when previous-sample growth is at or above this value.', 'GB', 1, 1, 0, NULL, 160),
('LogFileGrowthSpike', 'High24hGrowthGb', N'High 24-hour growth', N'High severity when 24-hour growth is at or above this value.', 'GB', 2, 2, 0, NULL, 170),
('LogFileGrowthSpike', 'High7dGrowthGb', N'High 7-day growth', N'High severity when 7-day growth is at or above this value.', 'GB', 5, 5, 0, NULL, 180),
('LogFileGrowthSpike', 'HighPercentGrowthMinimumLogGb', N'High percent-growth minimum log size', N'Current log size must be at or above this value before percentage-only growth can make the alert High.', 'GB', 1, 1, 0, NULL, 190),
('LogFileGrowthSpike', 'HighGrowthPercent', N'High growth percent', N'High severity when percentage growth reaches this value and minimum log size is met.', 'percent', 500, 500, 0, NULL, 200),
('LogFileGrowthSpike', 'CriticalPreviousGrowthGb', N'Critical previous-sample growth', N'Critical severity when previous-sample growth is at or above this value.', 'GB', 5, 5, 0, NULL, 210),
('LogFileGrowthSpike', 'Critical24hGrowthGb', N'Critical 24-hour growth', N'Critical severity when 24-hour growth is at or above this value.', 'GB', 10, 10, 0, NULL, 220),
('LogFileGrowthSpike', 'Critical7dGrowthGb', N'Critical 7-day growth', N'Critical severity when 7-day growth is at or above this value.', 'GB', 20, 20, 0, NULL, 230),
('LogFileGrowthSpike', 'CriticalBlockedPreviousGrowthGb', N'Critical blocked previous growth', N'Critical severity when log reuse is blocked and previous-sample growth is at or above this value.', 'GB', 1, 1, 0, NULL, 240),
('LogFileGrowthSpike', 'CriticalBlocked24hGrowthGb', N'Critical blocked 24-hour growth', N'Critical severity when log reuse is blocked and 24-hour growth is at or above this value.', 'GB', 2, 2, 0, NULL, 250),
('LogFileGrowthSpike', 'CriticalBlocked7dGrowthGb', N'Critical blocked 7-day growth', N'Critical severity when log reuse is blocked and 7-day growth is at or above this value.', 'GB', 5, 5, 0, NULL, 260),

('FullRecoveryNoLogBackup', 'CriticalStaleHours', N'Critical stale log backup age', N'Critical when latest observed log backup is older than this many hours.', 'hours', 72, 72, 0, NULL, 10),
('FullRecoveryNoLogBackup', 'AlertStaleHours', N'Alert stale log backup age', N'Raises an alert when latest observed log backup is older than this many hours.', 'hours', 24, 24, 0, NULL, 20),

('LongRunningTransaction', 'LookbackHours', N'Collection lookback', N'Only long-running transaction samples collected within this many hours are considered.', 'hours', 2, 2, 0, NULL, 10),
('LongRunningTransaction', 'AlertDurationMinutes', N'Alert duration', N'Raises an alert when an open transaction has been running at least this many minutes.', 'minutes', 60, 60, 0, NULL, 20),
('LongRunningTransaction', 'CriticalDurationMinutes', N'Critical duration', N'Critical severity when an open transaction has been running at least this many minutes.', 'minutes', 240, 240, 0, NULL, 30),

('BlockingChain', 'LookbackMinutes', N'Collection lookback', N'Only blocking samples collected within this many minutes are considered.', 'minutes', 30, 30, 0, NULL, 10),
('BlockingChain', 'CriticalBlockedSessionCount', N'Critical blocked session count', N'Critical when a blocker is blocking at least this many sessions.', 'sessions', 5, 5, 0, NULL, 20),
('BlockingChain', 'CriticalMaxBlockedWaitMs', N'Critical blocked wait', N'Critical when the longest blocked wait is at or above this value.', 'milliseconds', 600000, 600000, 0, NULL, 30),
('BlockingChain', 'CriticalLeadBlockerDurationMinutes', N'Critical lead blocker duration', N'Critical when the lead blocker has been running at least this many minutes.', 'minutes', 30, 30, 0, NULL, 40),

('ActiveTransactionLogReuseWait', 'BlockingLookbackMinutes', N'Blocking evidence lookback', N'Blocking evidence collected within this many minutes can make ACTIVE_TRANSACTION log reuse wait Critical.', 'minutes', 30, 30, 0, NULL, 10),
('ActiveTransactionLogReuseWait', 'LongTransactionLookbackHours', N'Long transaction evidence lookback', N'Long transaction evidence collected within this many hours is attached to ACTIVE_TRANSACTION log reuse alerts.', 'hours', 2, 2, 0, NULL, 20),

('AlwaysOnHealthIssue', 'LookbackMinutes', N'Collection lookback', N'Only Always On health samples collected within this many minutes are considered.', 'minutes', 30, 30, 0, NULL, 10),
('AlwaysOnLogReuseWait', 'EvidenceLookbackHours', N'Evidence lookback', N'Always On evidence collected within this many hours is attached to log reuse wait alerts.', 'hours', 2, 2, 0, NULL, 10),

('ReplicationAgentIssue', 'LookbackHours', N'Collection lookback', N'Only replication health samples collected within this many hours are considered.', 'hours', 2, 2, 0, NULL, 10),
('ReplicationLogReuseWait', 'CriticalEvidenceLookbackHours', N'Critical evidence lookback', N'Replication evidence collected within this many hours can make replication log reuse wait Critical.', 'hours', 2, 2, 0, NULL, 10),
('ReplicationLogReuseWait', 'EvidenceDetailsLookbackHours', N'Detail evidence lookback', N'Replication evidence collected within this many hours is attached to replication log reuse wait details.', 'hours', 4, 4, 0, NULL, 20),

('TempDBUsage', 'CriticalUsedPercent', N'Critical used percent', N'Critical when TempDB used percent is at or above this value.', 'percent', 95, 95, 0, 100, 10),
('TempDBUsage', 'AlertUsedPercent', N'Alert used percent', N'Raises an alert when TempDB used percent is at or above this value.', 'percent', 80, 80, 0, 100, 20),
('TempDBUsage', 'SessionLookbackMinutes', N'Session consumer lookback', N'TempDB session consumer evidence collected within this many minutes is attached to the alert.', 'minutes', 30, 30, 0, NULL, 30),

('DiskSpaceLow', 'CriticalAvailableGb', N'Critical free space', N'Critical when available volume space is at or below this value.', 'GB', 10, 10, 0, NULL, 10),
('DiskSpaceLow', 'CriticalUsedPercent', N'Critical used percent', N'Critical when volume used percent is at or above this value.', 'percent', 95, 95, 0, 100, 20),
('DiskSpaceLow', 'AlertAvailableGb', N'Alert free space', N'Raises an alert when available volume space is at or below this value.', 'GB', 20, 20, 0, NULL, 30),
('DiskSpaceLow', 'AlertUsedPercent', N'Alert used percent', N'Raises an alert when volume used percent is at or above this value.', 'percent', 90, 90, 0, 100, 40),

('BackupGrowth', 'BaselineDays', N'Baseline window', N'Backup growth compares latest backup with backups captured in this many prior days.', 'days', 30, 30, 1, NULL, 10),
('BackupGrowth', 'SizeMultiplier', N'Size multiplier', N'Raises an alert when latest backup size is at least this many times the baseline average.', 'multiplier', 1.5, 1.5, 0, NULL, 20),
('BackupGrowth', 'MinimumGrowthGb', N'Minimum backup growth', N'Raises an alert only when latest backup is at least this many GB above baseline average.', 'GB', 5, 5, 0, NULL, 30);

MERGE dbo.AlertThresholdSetting AS target
USING @Defaults AS source
    ON source.alert_type = target.alert_type
   AND source.setting_key = target.setting_key
WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        alert_type,
        setting_key,
        display_name,
        description,
        unit,
        setting_value_decimal,
        default_value_decimal,
        minimum_value_decimal,
        maximum_value_decimal,
        sort_order,
        updated_by
    )
    VALUES
    (
        source.alert_type,
        source.setting_key,
        source.display_name,
        source.description,
        source.unit,
        source.setting_value_decimal,
        source.default_value_decimal,
        source.minimum_value_decimal,
        source.maximum_value_decimal,
        source.sort_order,
        SUSER_SNAME()
    )
WHEN MATCHED THEN
    UPDATE SET
        display_name = source.display_name,
        description = source.description,
        unit = source.unit,
        default_value_decimal = source.default_value_decimal,
        minimum_value_decimal = source.minimum_value_decimal,
        maximum_value_decimal = source.maximum_value_decimal,
        sort_order = source.sort_order;
GO
