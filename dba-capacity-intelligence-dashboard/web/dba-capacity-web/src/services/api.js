const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5088/api';

async function request(path) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: {
      Accept: 'application/json'
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

  return response.json();
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
  getServers: () => request('/servers')
};
