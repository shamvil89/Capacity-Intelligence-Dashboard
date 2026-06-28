USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_ActiveAlerts
AS
SELECT
    alert_id,
    alert_time,
    server_name,
    database_name,
    alert_type,
    severity,
    message,
    source_script,
    details_json
FROM dbo.AlertHistory
WHERE is_resolved = 0;
GO
