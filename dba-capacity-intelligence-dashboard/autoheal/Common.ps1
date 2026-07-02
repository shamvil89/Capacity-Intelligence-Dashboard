[CmdletBinding()]
param()

function ConvertTo-SqlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    [string]$Value
}

function ConvertTo-SqlNumber {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    $Value
}

function ConvertTo-IsoDateTimeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    ([datetime]$Value).ToString('o')
}

function Get-AlertThresholdDecimal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AlertType,

        [Parameter(Mandatory = $true)]
        [string]$SettingKey,

        [Parameter(Mandatory = $true)]
        [decimal]$DefaultValue
    )

    $query = @"
SELECT TOP (1) setting_value_decimal
FROM dbo.AlertThresholdSetting
WHERE alert_type = @alert_type
  AND setting_key = @setting_key;
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{
        alert_type = $AlertType
        setting_key = $SettingKey
    })

    if ($rows.Count -eq 0 -or $null -eq $rows[0].setting_value_decimal -or $rows[0].setting_value_decimal -is [System.DBNull]) {
        return $DefaultValue
    }

    [decimal]$rows[0].setting_value_decimal
}

function Add-AutoHealWorkNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NoteType,

        [Parameter(Mandatory = $true)]
        [string]$NoteSource,

        [Parameter(Mandatory = $true)]
        [string]$CreatedBy,

        [string]$NoteText,

        [AllowNull()]
        [string]$DetailsJson
    )

    $query = @"
IF OBJECT_ID(N'dbo.AlertWorkNote', N'U') IS NOT NULL
BEGIN
    INSERT INTO dbo.AlertWorkNote
    (
        alert_id,
        request_id,
        note_type,
        note_source,
        created_by,
        note_text,
        details_json
    )
    SELECT
        request.alert_id,
        request.request_id,
        @note_type,
        @note_source,
        @created_by,
        COALESCE(NULLIF(@note_text, N''), N'Auto-heal status updated.'),
        @details_json
    FROM dbo.AutoHealRequest AS request
    WHERE request.request_id = CONVERT(uniqueidentifier, @request_id)
      AND request.alert_id IS NOT NULL
      AND EXISTS
      (
          SELECT 1
          FROM dbo.AlertHistory AS alert
          WHERE alert.alert_id = request.alert_id
      );
END;
"@

    Invoke-RepositoryQuery -Query $query -SqlParameter @{
        request_id = $RequestId.ToString()
        note_type = $NoteType
        note_source = $NoteSource
        created_by = $CreatedBy
        note_text = $NoteText
        details_json = $DetailsJson
    } | Out-Null
}

function Set-AutoHealRequestStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message,

        [AllowNull()]
        [string]$DetailsJson
    )

    $completedAtExpression = if ($Status -in @('Completed', 'Failed', 'CompletedWithWarnings')) { 'SYSUTCDATETIME()' } else { 'completed_at' }
    $query = @"
UPDATE dbo.AutoHealRequest
SET status = @status,
    message = @message,
    details_json = COALESCE(@details_json, details_json),
    completed_at = $completedAtExpression
WHERE request_id = CONVERT(uniqueidentifier, @request_id);
"@

    Invoke-RepositoryQuery -Query $query -SqlParameter @{
        request_id = $RequestId.ToString()
        status = $Status
        message = $Message
        details_json = $DetailsJson
    } | Out-Null

    $noteType = switch ($Status) {
        'Running' { 'AutoHealRunning'; break }
        'CleanupRunning' { 'AutoHealCleanupRunning'; break }
        'Completed' { 'AutoHealCompleted'; break }
        'CompletedWithWarnings' { 'AutoHealCompletedWithWarnings'; break }
        'Failed' { 'AutoHealFailed'; break }
        default { "AutoHeal$Status" }
    }

    Add-AutoHealWorkNote `
        -NoteType $noteType `
        -NoteSource 'AutoHealPipeline' `
        -CreatedBy 'Auto Heal Pipeline' `
        -NoteText $Message `
        -DetailsJson $DetailsJson
}

function Get-SourceInventoryRow {
    $query = @"
SELECT TOP (1)
    server_name,
    connection_mode,
    credential_key
FROM dbo.ServerInventory
WHERE is_active = 1
  AND
  (
      server_name = @server_name
      OR LEFT(server_name, CHARINDEX(N'.', server_name + N'.') - 1) = @server_name
      OR server_name = LEFT(@server_name, CHARINDEX(N'.', @server_name + N'.') - 1)
  )
ORDER BY CASE WHEN server_name = @server_name THEN 0 ELSE 1 END;
"@

    $rows = @(Invoke-RepositoryQuery -Query $query -SqlParameter @{ server_name = $ServerName })
    if ($rows.Count -eq 0) {
        return $null
    }

    $rows[0]
}

function Set-SourceConnectionEnvironment {
    $inventory = Get-SourceInventoryRow
    if ($null -eq $inventory) {
        Write-Warning "ServerInventory row not found for $ServerName. Falling back to default source connection settings."
        return
    }

    $env:DBA_SOURCE_CONNECTION_MODE = [string]$inventory.connection_mode
    $env:DBA_SOURCE_CREDENTIAL_KEY = if ($inventory.credential_key) { [string]$inventory.credential_key } else { 'default' }
}
