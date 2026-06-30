using DBA.Capacity.Api.Models;
using DBA.Capacity.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DBA.Capacity.Api.Controllers;

[ApiController]
[Route("api/settings")]
public sealed class SettingsController(ISettingsService settingsService) : ControllerBase
{
    [HttpGet("alert-thresholds")]
    [ProducesResponseType(typeof(IReadOnlyList<AlertThresholdSettingItem>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<AlertThresholdSettingItem>>> GetAlertThresholds(CancellationToken cancellationToken)
    {
        var rows = await settingsService.GetAlertThresholdsAsync(cancellationToken);
        return Ok(rows);
    }

    [HttpPut("alert-thresholds/{settingId:int}")]
    [ProducesResponseType(typeof(AlertThresholdSettingItem), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AlertThresholdSettingItem>> UpdateAlertThreshold(
        int settingId,
        [FromBody] UpdateAlertThresholdSettingRequest request,
        CancellationToken cancellationToken)
    {
        var existing = await settingsService.GetAlertThresholdAsync(settingId, cancellationToken);
        if (existing is null)
        {
            return NotFound();
        }

        var validationError = ValidateThresholdValue(existing, request.SettingValueDecimal);
        if (validationError is not null)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = validationError
            });
        }

        var updated = await settingsService.UpdateAlertThresholdAsync(settingId, request.SettingValueDecimal, cancellationToken);
        return updated is null ? NotFound() : Ok(updated);
    }

    [HttpPost("alert-thresholds/{settingId:int}/reset")]
    [ProducesResponseType(typeof(AlertThresholdSettingItem), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<AlertThresholdSettingItem>> ResetAlertThreshold(int settingId, CancellationToken cancellationToken)
    {
        var updated = await settingsService.ResetAlertThresholdAsync(settingId, cancellationToken);
        return updated is null ? NotFound() : Ok(updated);
    }

    private static string? ValidateThresholdValue(AlertThresholdSettingItem setting, decimal value)
    {
        if (setting.MinimumValueDecimal is not null && value < setting.MinimumValueDecimal.Value)
        {
            return $"{setting.DisplayName} must be greater than or equal to {setting.MinimumValueDecimal.Value}.";
        }

        if (setting.MaximumValueDecimal is not null && value > setting.MaximumValueDecimal.Value)
        {
            return $"{setting.DisplayName} must be less than or equal to {setting.MaximumValueDecimal.Value}.";
        }

        return null;
    }
}
