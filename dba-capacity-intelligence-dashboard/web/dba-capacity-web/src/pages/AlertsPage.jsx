import { useEffect, useState } from 'react';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import { formatDateTime } from '../components/formatters.js';
import { api } from '../services/api.js';

export default function AlertsPage() {
  const [alerts, setAlerts] = useState([]);
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
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Server</th>
                  <th>Database</th>
                  <th>Alert Type</th>
                  <th>Severity</th>
                  <th>Message</th>
                </tr>
              </thead>
              <tbody>
                {alerts.map((item) => (
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
        </div>
      </DataState>
    </section>
  );
}
