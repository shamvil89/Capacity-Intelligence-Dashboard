USE [DBAUtility];
GO

IF OBJECT_ID(N'dbo.ApplicationCmdb', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApplicationCmdb
    (
        application_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApplicationCmdb PRIMARY KEY,
        application_name NVARCHAR(250) NOT NULL,
        prodops_team_email NVARCHAR(500) NULL,
        application_owner_email NVARCHAR(500) NULL,
        business_owner_email NVARCHAR(500) NULL,
        support_dl_email NVARCHAR(500) NULL,
        escalation_dl_email NVARCHAR(500) NULL,
        servicenow_group NVARCHAR(250) NULL,
        criticality NVARCHAR(50) NULL,
        application_url NVARCHAR(1000) NULL,
        notes NVARCHAR(MAX) NULL,
        created_at DATETIME2(7) NOT NULL CONSTRAINT DF_ApplicationCmdb_created_at DEFAULT (SYSUTCDATETIME()),
        created_by SYSNAME NULL,
        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_ApplicationCmdb_updated_at DEFAULT (SYSUTCDATETIME()),
        updated_by SYSNAME NULL,
        CONSTRAINT UQ_ApplicationCmdb_ApplicationName UNIQUE (application_name)
    );
END;
GO

IF OBJECT_ID(N'dbo.ApplicationDatabaseMapping', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApplicationDatabaseMapping
    (
        mapping_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApplicationDatabaseMapping PRIMARY KEY,
        application_id INT NOT NULL,
        server_name NVARCHAR(256) NOT NULL,
        database_name NVARCHAR(256) NOT NULL,
        environment NVARCHAR(50) NULL,
        is_active BIT NOT NULL CONSTRAINT DF_ApplicationDatabaseMapping_is_active DEFAULT (1),
        created_at DATETIME2(7) NOT NULL CONSTRAINT DF_ApplicationDatabaseMapping_created_at DEFAULT (SYSUTCDATETIME()),
        created_by SYSNAME NULL,
        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_ApplicationDatabaseMapping_updated_at DEFAULT (SYSUTCDATETIME()),
        updated_by SYSNAME NULL,
        CONSTRAINT FK_ApplicationDatabaseMapping_ApplicationCmdb
            FOREIGN KEY (application_id)
            REFERENCES dbo.ApplicationCmdb(application_id)
            ON DELETE CASCADE,
        CONSTRAINT UQ_ApplicationDatabaseMapping_ServerDatabase UNIQUE (server_name, database_name)
    );

    CREATE INDEX IX_ApplicationDatabaseMapping_Application
        ON dbo.ApplicationDatabaseMapping(application_id, is_active, server_name, database_name);
END;
GO
