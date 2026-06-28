import { useEffect, useMemo, useState } from 'react';
import { Info, X } from 'lucide-react';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { useTimezone } from '../components/TimezoneContext.jsx';
import { formatDateTime } from '../components/formatters.js';
import { containsText, getUniqueOptions, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

export default function AlertsPage() {
  const { effectiveTimeZone } = useTimezone();
  const [alerts, setAlerts] = useState([]);
  const [selectedAlert, setSelectedAlert] = useState(null);
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
        'message',
        'sourceScript',
        'detailsJson'
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
        <div className="table-panel alerts-panel">
          <div className="table-panel-header">
            <h3>Alert Queue</h3>
            <span>{visibleAlerts.length} rows</span>
          </div>

          <div className="table-controls alerts-controls">
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
              <table className="alerts-table">
                <thead>
                  <tr>
                    <th><SortableHeader label="Time" sortKey="alertTime" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Alert Type" sortKey="alertType" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Severity" sortKey="severity" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Message" sortKey="message" sortState={sortState} onSort={handleSort} /></th>
                    <th>More Info</th>
                  </tr>
                </thead>
                <tbody>
                  {visibleAlerts.map((item) => (
                    <tr key={item.alertId ?? `${item.alertTime}-${item.serverName}-${item.alertType}`}>
                      <td>{formatDateTime(item.alertTime, effectiveTimeZone)}</td>
                      <td>{item.serverName}</td>
                      <td>{item.databaseName || '-'}</td>
                      <td>{item.alertType}</td>
                      <td><RiskBadge level={item.severity} /></td>
                      <td className="recommendation-cell alert-message-cell">{item.message}</td>
                      <td>
                        <button type="button" className="secondary-action" onClick={() => setSelectedAlert(item)}>
                          <Info aria-hidden="true" size={14} />
                          More info
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </DataState>
        </div>
      </DataState>

      {selectedAlert ? (
        <AlertDetailsModal
          alert={selectedAlert}
          effectiveTimeZone={effectiveTimeZone}
          onClose={() => setSelectedAlert(null)}
        />
      ) : null}
    </section>
  );
}

function AlertDetailsModal({ alert, effectiveTimeZone, onClose }) {
  const details = parseAlertDetails(alert.detailsJson);

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="modal-panel" role="dialog" aria-modal="true" aria-labelledby="alert-details-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <div>
            <p className="eyebrow">Alert evidence</p>
            <h3 id="alert-details-title">{alert.alertType}</h3>
          </div>
          <button type="button" className="icon-action" aria-label="Close details" onClick={onClose}>
            <X aria-hidden="true" size={18} />
          </button>
        </div>

        <div className="modal-body">
          <div className="detail-summary-grid">
            <DetailItem label="Time" value={formatDateTime(alert.alertTime, effectiveTimeZone)} />
            <DetailItem label="Server" value={alert.serverName} />
            <DetailItem label="Database" value={alert.databaseName || '-'} />
            <DetailItem label="Severity" value={alert.severity} />
            <DetailItem label="Source" value={alert.sourceScript || details?.sourceScripts || '-'} wide />
          </div>

          <section className="modal-section">
            <h4>Message</h4>
            <p>{alert.message}</p>
          </section>

          <section className="modal-section">
            <h4>Evidence</h4>
            {details ? <StructuredDetails value={details} /> : <p>No structured details were stored for this alert.</p>}
          </section>
        </div>
      </section>
    </div>
  );
}

function DetailItem({ label, value, wide = false }) {
  return (
    <div className={wide ? 'detail-item detail-item-wide' : 'detail-item'}>
      <span>{label}</span>
      <strong>{formatDetailValue(value)}</strong>
    </div>
  );
}

function StructuredDetails({ value }) {
  if (Array.isArray(value)) {
    return (
      <div className="nested-detail-list">
        {value.map((item, index) => (
          <div className="nested-detail" key={index}>
            <StructuredDetails value={item} />
          </div>
        ))}
      </div>
    );
  }

  if (value && typeof value === 'object') {
    return (
      <div className="detail-key-values">
        {Object.entries(value).map(([key, itemValue]) => (
          <div className="detail-row" key={key}>
            <span>{formatDetailLabel(key)}</span>
            <div>{renderDetailValue(itemValue)}</div>
          </div>
        ))}
      </div>
    );
  }

  return <span>{formatDetailValue(value)}</span>;
}

function renderDetailValue(value) {
  if (Array.isArray(value) || (value && typeof value === 'object')) {
    return <StructuredDetails value={value} />;
  }

  return <span>{formatDetailValue(value)}</span>;
}

function parseAlertDetails(detailsJson) {
  if (!detailsJson) {
    return null;
  }

  try {
    return JSON.parse(detailsJson);
  } catch {
    return {
      rawDetails: detailsJson
    };
  }
}

function formatDetailLabel(value) {
  return String(value)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatDetailValue(value) {
  if (value === null || value === undefined || value === '') {
    return '-';
  }

  if (Array.isArray(value)) {
    return value.join(', ');
  }

  return String(value);
}
