USE [DBAUtility];
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ServerInventory WHERE server_name = N'localhost')
BEGIN
    INSERT INTO dbo.ServerInventory
    (
        server_name,
        environment,
        server_type,
        connection_mode,
        is_active
    )
    VALUES
    (
        N'localhost',
        'Development',
        'SQLServer',
        'SqlAuth',
        0
    );
END;
GO
