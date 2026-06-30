using DBA.Capacity.Api.Models;

namespace DBA.Capacity.Api.Services;

public interface ISettingsService
{
    Task<IReadOnlyList<AlertThresholdSettingItem>> GetAlertThresholdsAsync(CancellationToken cancellationToken);
    Task<AlertThresholdSettingItem?> GetAlertThresholdAsync(int settingId, CancellationToken cancellationToken);
    Task<AlertThresholdSettingItem?> UpdateAlertThresholdAsync(int settingId, decimal settingValueDecimal, CancellationToken cancellationToken);
    Task<AlertThresholdSettingItem?> ResetAlertThresholdAsync(int settingId, CancellationToken cancellationToken);
}
