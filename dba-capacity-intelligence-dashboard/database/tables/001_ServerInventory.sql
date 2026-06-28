USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.ServerInventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ServerInventory
    (
        server_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ServerInventory PRIMARY KEY,
        server_name SYSNAME NOT NULL,
        environment VARCHAR(50) NOT NULL,
        server_type VARCHAR(50) NOT NULL,
        connection_mode VARCHAR(50) NULL,
        credential_key VARCHAR(100) NULL,
        is_active BIT NOT NULL CONSTRAINT DF_ServerInventory_is_active DEFAULT (1),
        created_at DATETIME2(7) NOT NULL CONSTRAINT DF_ServerInventory_created_at DEFAULT (SYSUTCDATETIME()),
        updated_at DATETIME2(7) NULL,
        CONSTRAINT UQ_ServerInventory_server_name UNIQUE (server_name),
        CONSTRAINT CK_ServerInventory_server_type CHECK (server_type IN ('SQLServer', 'AzureSQL', 'ManagedInstance')),
        CONSTRAINT CK_ServerInventory_connection_mode CHECK (connection_mode IS NULL OR connection_mode IN ('SqlAuth', 'WindowsAuth', 'AzureADPassword', 'AzureADIntegrated', 'ManagedIdentity'))
    );
END;
GO

IF COL_LENGTH(N'dbo.ServerInventory', N'credential_key') IS NULL
BEGIN
    ALTER TABLE dbo.ServerInventory
        ADD credential_key VARCHAR(100) NULL;
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = N'CK_ServerInventory_connection_mode'
      AND parent_object_id = OBJECT_ID(N'dbo.ServerInventory')
)
BEGIN
    ALTER TABLE dbo.ServerInventory
        DROP CONSTRAINT CK_ServerInventory_connection_mode;
END;
GO

ALTER TABLE dbo.ServerInventory
    ADD CONSTRAINT CK_ServerInventory_connection_mode
    CHECK
    (
        connection_mode IS NULL
        OR connection_mode IN
        (
            'SqlAuth',
            'WindowsAuth',
            'AzureADPassword',
            'AzureADIntegrated',
            'ManagedIdentity'
        )
    );
GO
