USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_ActiveAlerts
AS
SELECT
    a.alert_id,
    a.alert_time,
    a.server_name,
    si.environment,
    a.database_name,
    a.alert_type,
    a.severity,
    a.message,
    a.source_script,
    a.details_json
FROM dbo.AlertHistory AS a
LEFT JOIN dbo.ServerInventory AS si
    ON si.server_name = a.server_name
WHERE a.is_resolved = 0;
GO
