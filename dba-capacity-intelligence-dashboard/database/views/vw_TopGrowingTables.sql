USE [DBAUtility];
GO

CREATE OR ALTER VIEW dbo.vw_TopGrowingTables
AS
WITH LatestTable AS
(
    SELECT
        t.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY t.server_name, t.database_name, t.schema_name, t.table_name
            ORDER BY t.collection_time DESC, t.id DESC
        ) AS rn
    FROM dbo.TableSizeHistory AS t
)
SELECT
    l.server_name,
    si.environment,
    l.database_name,
    l.schema_name,
    l.table_name,
    l.total_mb AS current_size_mb,
    p.total_mb AS size_30_days_ago_mb,
    l.total_mb - p.total_mb AS growth_30d_mb,
    l.row_count AS current_row_count,
    l.row_count - p.row_count AS row_growth_30d
FROM LatestTable AS l
OUTER APPLY
(
    SELECT TOP (1)
        si.environment
    FROM dbo.ServerInventory AS si
    WHERE si.server_name = l.server_name
       OR
       (
           CHARINDEX(N'.', si.server_name) > 0
           AND LEFT(si.server_name, CHARINDEX(N'.', si.server_name) - 1) = l.server_name
       )
    ORDER BY CASE WHEN si.server_name = l.server_name THEN 0 ELSE 1 END
) AS si
OUTER APPLY
(
    SELECT TOP (1)
        h.total_mb,
        h.row_count
    FROM dbo.TableSizeHistory AS h
    WHERE h.server_name = l.server_name
      AND h.database_name = l.database_name
      AND h.schema_name = l.schema_name
      AND h.table_name = l.table_name
      AND h.collection_time < l.collection_time
    ORDER BY ABS(DATEDIFF_BIG(SECOND, h.collection_time, DATEADD(DAY, -30, l.collection_time)))
) AS p
WHERE l.rn = 1;
GO
