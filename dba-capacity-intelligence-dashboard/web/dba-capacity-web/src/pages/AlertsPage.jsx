import { useEffect, useMemo, useState } from 'react';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { formatDateTime } from '../components/formatters.js';
import { containsText, getUniqueOptions, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

export default function AlertsPage() {
  const [alerts, setAlerts] = useState([]);
  const [containsFilter, setContainsFilter] = useState('');
  const [serverFilter, setServerFilter] = useState('All');
  const [severityFilter, setSeverityFilter] = useState('All');
  const [alertTypeFilter, setAlertTypeFilter] = useState('All');
  const [sortState, setSortState] = useState({ key: 'alertTime', direction: 'desc' });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = await api.getActiveAlerts();
        if (isMounted) {
          setAlerts(rows);
        }
      } catch (err) {
        if (isMounted) {
          setError(err.message);
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    load();
    return () => {
      isMounted = false;
    };
  }, []);

  const serverOptions = useMemo(() => getUniqueOptions(alerts, 'serverName'), [alerts]);
  const severityOptions = useMemo(() => getUniqueOptions(alerts, 'severity'), [alerts]);
  const alertTypeOptions = useMemo(() => getUniqueOptions(alerts, 'alertType'), [alerts]);

  const visibleAlerts = useMemo(() => {
    const filteredRows = alerts.filter((item) => {
      const matchesServer = serverFilter === 'All' || item.serverName === serverFilter;
      const matchesSeverity = severityFilter === 'All' || item.severity === severityFilter;
      const matchesAlertType = alertTypeFilter === 'All' || item.alertType === alertTypeFilter;
      const matchesContains = containsText(item, [
        'serverName',
        'databaseName',
        'alertType',
        'severity',
        'message'
      ], containsFilter);

      return matchesServer && matchesSeverity && matchesAlertType && matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      alertTime: 'date',
      severity: 'risk'
    });
  }, [alertTypeFilter, alerts, containsFilter, serverFilter, severityFilter, sortState]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Active Alerts</h2>
          <p className="subtle">Unresolved repository alerts from forecast and collector runs.</p>
        </div>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={alerts.length === 0}>
        <div className="table-panel">
          <div className="table-panel-header">
            <h3>Alert Queue</h3>
            <span>{visibleAlerts.length} rows</span>
          </div>

          <div className="table-controls">
            <label className="search-control">
              <span>Contains</span>
              <input
                type="search"
                value={containsFilter}
                onChange={(event) => setContainsFilter(event.target.value)}
                placeholder="Server, database, type, message"
              />
            </label>

            <label className="filter-control">
              <span>Server</span>
              <select value={serverFilter} onChange={(event) => setServerFilter(event.target.value)}>
                <option value="All">All</option>
                {serverOptions.map((serverName) => (
                  <option key={serverName} value={serverName}>{serverName}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Severity</span>
              <select value={severityFilter} onChange={(event) => setSeverityFilter(event.target.value)}>
                <option value="All">All</option>
                {severityOptions.map((severity) => (
                  <option key={severity} value={severity}>{severity}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Type</span>
              <select value={alertTypeFilter} onChange={(event) => setAlertTypeFilter(event.target.value)}>
                <option value="All">All</option>
                {alertTypeOptions.map((alertType) => (
                  <option key={alertType} value={alertType}>{alertType}</option>
                ))}
              </select>
            </label>
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleAlerts.length === 0}>
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th><SortableHeader label="Time" sortKey="alertTime" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Alert Type" sortKey="alertType" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Severity" sortKey="severity" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Message" sortKey="message" sortState={sortState} onSort={handleSort} /></th>
                </tr>
              </thead>
              <tbody>
                {visibleAlerts.map((item) => (
                  <tr key={`${item.alertTime}-${item.serverName}-${item.alertType}`}>
                    <td>{formatDateTime(item.alertTime)}</td>
                    <td>{item.serverName}</td>
                    <td>{item.databaseName || '-'}</td>
                    <td>{item.alertType}</td>
                    <td><RiskBadge level={item.severity} /></td>
                    <td className="recommendation-cell">{item.message}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </DataState>
        </div>
      </DataState>
    </section>
  );
}
