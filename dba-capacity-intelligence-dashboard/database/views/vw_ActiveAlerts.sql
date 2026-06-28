USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_ActiveAlerts
AS
SELECT
    a.alert_id,
    a.alert_time,
    a.alert_key,
    a.server_name,
    si.environment,
    a.database_name,
    a.alert_type,
    a.severity,
    a.message,
    a.source_script,
    a.details_json,
    a.is_resolved,
    a.resolved_at
FROM dbo.AlertHistory AS a
OUTER APPLY
(
    SELECT TOP (1)
        si.environment
    FROM dbo.ServerInventory AS si
    WHERE si.server_name = a.server_name
       OR
       (
           CHARINDEX(N'.', si.server_name) > 0
           AND LEFT(si.server_name, CHARINDEX(N'.', si.server_name) - 1) = a.server_name
       )
    ORDER BY CASE WHEN si.server_name = a.server_name THEN 0 ELSE 1 END
) AS si
WHERE a.is_resolved = 0;
GO
