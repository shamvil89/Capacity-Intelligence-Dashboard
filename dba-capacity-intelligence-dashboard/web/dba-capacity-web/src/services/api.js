const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5088/api';

async function request(path, options = {}) {
  const { headers, ...fetchOptions } = options;
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...fetchOptions,
    headers: {
      Accept: 'application/json',
      ...(headers ?? {})
    }
  });

  if (!response.ok) {
    let message = 'The dashboard service could not complete the request.';

    try {
      const body = await response.json();
      message = body.message || body.title || message;
    } catch {
      message = `${message} Status: ${response.status}`;
    }

    throw new Error(message);
  }

  if (response.status === 204) {
    return null;
  }

  const body = await response.text();
  return body ? JSON.parse(body) : null;
}

function toQueryString(params) {
  const searchParams = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      searchParams.append(key, value);
    }
  });

  const query = searchParams.toString();
  return query ? `?${query}` : '';
}

export const api = {
  getSummary: (filters = {}) => request(`/dashboard/summary${toQueryString(filters)}`),
  getCapacityDatabases: (filters = {}) => request(`/capacity/databases${toQueryString(filters)}`),
  getDatabaseTrend: (serverName, databaseName, days = 90) =>
    request(`/capacity/databases/${encodeURIComponent(serverName)}/${encodeURIComponent(databaseName)}/trend${toQueryString({ days })}`),
  getTopGrowingTables: (limit = 20, filters = {}) => request(`/capacity/top-growing-tables${toQueryString({ limit, ...filters })}`),
  getActiveAlerts: () => request('/alerts/active'),
  getAlertHistory: (limit = 250) => request(`/alerts/history${toQueryString({ limit })}`),
  deleteAlert: (alertId) => request(`/alerts/${encodeURIComponent(alertId)}`, { method: 'DELETE' }),
  getAlertThresholds: () => request('/settings/alert-thresholds'),
  updateAlertThreshold: (settingId, settingValueDecimal) => request(`/settings/alert-thresholds/${encodeURIComponent(settingId)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ settingValueDecimal })
  }),
  resetAlertThreshold: (settingId) => request(`/settings/alert-thresholds/${encodeURIComponent(settingId)}/reset`, { method: 'POST' }),
  getCmdbEntries: () => request('/cmdb/applications'),
  getCmdbForDatabase: (serverName, databaseName) => request(`/cmdb/database${toQueryString({ serverName, databaseName })}`),
  upsertCmdbEntry: (entry) => request('/cmdb/applications', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(entry)
  }),
  importCmdbEntries: (entries) => request('/cmdb/applications/import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ entries })
  }),
  deleteCmdbMapping: (mappingId) => request(`/cmdb/database-mappings/${encodeURIComponent(mappingId)}`, { method: 'DELETE' }),
  deleteCmdbApplication: (applicationId) => request(`/cmdb/applications/${encodeURIComponent(applicationId)}`, { method: 'DELETE' }),
  getServers: () => request('/servers'),
  getCollectorRunStatus: () => request('/collector-run'),
  queueCollectorRun: () => request('/collector-run', { method: 'POST' })
};
