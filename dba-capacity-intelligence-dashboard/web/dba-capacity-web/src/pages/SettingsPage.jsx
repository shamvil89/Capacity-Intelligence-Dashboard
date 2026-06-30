import { useCallback, useEffect, useMemo, useState } from 'react';
import { RotateCcw, Save } from 'lucide-react';
import DataState from '../components/DataState.jsx';
import { api } from '../services/api.js';

export default function SettingsPage() {
  const [thresholds, setThresholds] = useState([]);
  const [draftValues, setDraftValues] = useState({});
  const [rowStatus, setRowStatus] = useState({});
  const [query, setQuery] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const loadThresholds = useCallback(async () => {
    setIsLoading(true);
    setError('');

    try {
      const rows = await api.getAlertThresholds();
      setThresholds(rows ?? []);
      setDraftValues(Object.fromEntries((rows ?? []).map((row) => [row.settingId, formatInputValue(row.settingValueDecimal)])));
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadThresholds();
  }, [loadThresholds]);

  const filteredThresholds = useMemo(() => {
    const tokens = query
      .split(',')
      .map((part) => part.trim().toLowerCase())
      .filter(Boolean);

    if (tokens.length === 0) {
      return thresholds;
    }

    return thresholds.filter((row) => {
      const haystack = [
        row.alertType,
        row.settingKey,
        row.displayName,
        row.description,
        row.unit
      ].join(' ').toLowerCase();

      return tokens.some((token) => haystack.includes(token));
    });
  }, [query, thresholds]);

  const groupedThresholds = useMemo(() => {
    const groups = new Map();

    filteredThresholds.forEach((row) => {
      if (!groups.has(row.alertType)) {
        groups.set(row.alertType, []);
      }

      groups.get(row.alertType).push(row);
    });

    return Array.from(groups.entries());
  }, [filteredThresholds]);

  function updateDraft(settingId, value) {
    setDraftValues((current) => ({ ...current, [settingId]: value }));
    setRowStatus((current) => ({ ...current, [settingId]: '' }));
  }

  async function saveThreshold(row) {
    const draftValue = draftValues[row.settingId] ?? '';
    const validationError = validateThresholdValue(row, draftValue);

    if (validationError) {
      setRowStatus((current) => ({ ...current, [row.settingId]: validationError }));
      return;
    }

    const value = Number(String(draftValue).trim());
    setRowStatus((current) => ({ ...current, [row.settingId]: 'Saving...' }));

    try {
      const updated = await api.updateAlertThreshold(row.settingId, value);
      replaceThreshold(updated);
      setRowStatus((current) => ({ ...current, [row.settingId]: 'Saved' }));
      window.setTimeout(() => setRowStatus((current) => ({ ...current, [row.settingId]: '' })), 1800);
    } catch (err) {
      setRowStatus((current) => ({ ...current, [row.settingId]: err.message }));
    }
  }

  async function resetThreshold(row) {
    setRowStatus((current) => ({ ...current, [row.settingId]: 'Resetting...' }));

    try {
      const updated = await api.resetAlertThreshold(row.settingId);
      replaceThreshold(updated);
      setRowStatus((current) => ({ ...current, [row.settingId]: 'Reset' }));
      window.setTimeout(() => setRowStatus((current) => ({ ...current, [row.settingId]: '' })), 1800);
    } catch (err) {
      setRowStatus((current) => ({ ...current, [row.settingId]: err.message }));
    }
  }

  function replaceThreshold(updated) {
    setThresholds((current) => current.map((row) => (row.settingId === updated.settingId ? updated : row)));
    setDraftValues((current) => ({ ...current, [updated.settingId]: formatInputValue(updated.settingValueDecimal) }));
  }

  const changedCount = thresholds.filter((row) => hasDraftChange(row, draftValues[row.settingId])).length;

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Settings</h2>
          <p className="subtle">Alert threshold tuning for repository forecast and collector-generated alerts.</p>
        </div>
        <div className="settings-summary">
          <span>{thresholds.length} thresholds</span>
          <span>{changedCount} unsaved</span>
        </div>
      </div>

      <div className="table-panel">
        <div className="table-controls">
          <label className="search-control">
            <span>Contains</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Alert type, setting, unit"
            />
          </label>
        </div>

        <DataState isLoading={isLoading} error={error} isEmpty={groupedThresholds.length === 0}>
          <div className="settings-groups">
            {groupedThresholds.map(([alertType, rows]) => (
              <section className="settings-group" key={alertType}>
                <div className="settings-group-header">
                  <h3>{alertType}</h3>
                  <span>{rows.length} thresholds</span>
                </div>
                <div className="table-scroll">
                  <table className="settings-table">
                    <thead>
                      <tr>
                        <th>Setting</th>
                        <th>Value</th>
                        <th>Default</th>
                        <th>Range</th>
                        <th>Description</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((row) => {
                        const draftValue = draftValues[row.settingId] ?? '';
                        const validationError = validateThresholdValue(row, draftValue);
                        const hasChange = hasDraftChange(row, draftValue);
                        const status = rowStatus[row.settingId] ?? '';
                        const isBusy = status === 'Saving...' || status === 'Resetting...';

                        return (
                          <tr key={row.settingId}>
                            <td>
                              <strong>{row.displayName}</strong>
                              <span className="setting-key">{row.settingKey}</span>
                            </td>
                            <td>
                              <div className="threshold-input-wrap">
                                <input
                                  className={validationError ? 'threshold-input invalid' : 'threshold-input'}
                                  type="number"
                                  step="0.0001"
                                  min={row.minimumValueDecimal ?? undefined}
                                  max={row.maximumValueDecimal ?? undefined}
                                  value={draftValue}
                                  onChange={(event) => updateDraft(row.settingId, event.target.value)}
                                />
                                <span>{row.unit || '-'}</span>
                              </div>
                              {status ? <span className={status === 'Saved' || status === 'Reset' ? 'setting-status success' : 'setting-status'}>{status}</span> : null}
                            </td>
                            <td>{formatThresholdValue(row.defaultValueDecimal)} {row.unit || ''}</td>
                            <td>{formatRange(row)}</td>
                            <td>{row.description || '-'}</td>
                            <td>
                              <div className="row-actions">
                                <button
                                  type="button"
                                  className="secondary-action"
                                  disabled={!hasChange || Boolean(validationError) || isBusy}
                                  onClick={() => saveThreshold(row)}
                                >
                                  <Save aria-hidden="true" size={14} />
                                  Save
                                </button>
                                <button
                                  type="button"
                                  className="secondary-action"
                                  disabled={isBusy || Number(row.settingValueDecimal) === Number(row.defaultValueDecimal)}
                                  onClick={() => resetThreshold(row)}
                                >
                                  <RotateCcw aria-hidden="true" size={14} />
                                  Reset
                                </button>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </section>
            ))}
          </div>
        </DataState>
      </div>
    </section>
  );
}

function hasDraftChange(row, draftValue) {
  const text = String(draftValue ?? '').trim();
  return text === '' || Number(text) !== Number(row.settingValueDecimal);
}

function validateThresholdValue(row, rawValue) {
  const text = String(rawValue ?? '').trim();

  if (text === '') {
    return 'Enter a number.';
  }

  const value = Number(text);

  if (!Number.isFinite(value)) {
    return 'Enter a number.';
  }

  if (row.minimumValueDecimal !== null && row.minimumValueDecimal !== undefined && value < Number(row.minimumValueDecimal)) {
    return `Minimum ${formatThresholdValue(row.minimumValueDecimal)}.`;
  }

  if (row.maximumValueDecimal !== null && row.maximumValueDecimal !== undefined && value > Number(row.maximumValueDecimal)) {
    return `Maximum ${formatThresholdValue(row.maximumValueDecimal)}.`;
  }

  return '';
}

function formatInputValue(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '';
  }

  return Number(value).toFixed(4).replace(/\.?0+$/, '');
}

function formatThresholdValue(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return Number(value).toLocaleString(undefined, {
    maximumFractionDigits: 4,
    minimumFractionDigits: 0
  });
}

function formatRange(row) {
  const minimum = row.minimumValueDecimal === null || row.minimumValueDecimal === undefined
    ? '-'
    : formatThresholdValue(row.minimumValueDecimal);
  const maximum = row.maximumValueDecimal === null || row.maximumValueDecimal === undefined
    ? '-'
    : formatThresholdValue(row.maximumValueDecimal);

  return `${minimum} to ${maximum}`;
}
