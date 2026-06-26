import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SummaryCard from '../components/SummaryCard.jsx';
import { formatInteger, formatNumber } from '../components/formatters.js';
import { api } from '../services/api.js';

const riskLevels = ['All', 'Healthy', 'Low', 'Medium', 'High', 'Critical'];

export default function DashboardPage() {
  const navigate = useNavigate();
  const [riskLevel, setRiskLevel] = useState('All');
  const [summary, setSummary] = useState(null);
  const [databases, setDatabases] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const [summaryResult, databaseResult] = await Promise.all([
          api.getSummary(),
          api.getCapacityDatabases({ riskLevel })
        ]);

        if (isMounted) {
          setSummary(summaryResult);
          setDatabases(databaseResult);
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
  }, [riskLevel]);

  const cards = useMemo(() => [
    { label: 'Total Servers', value: formatInteger(summary?.totalServers), accent: 'teal' },
    { label: 'Total Databases', value: formatInteger(summary?.totalDatabases), accent: 'green' },
    { label: 'Critical Alerts', value: formatInteger(summary?.criticalAlerts), accent: 'red' },
    { label: 'High Risk Databases', value: formatInteger(summary?.highRiskDatabases), accent: 'orange' },
    { label: 'Largest Database', value: summary?.largestDatabaseName || 'No data', accent: 'blue' },
    { label: 'Fastest Growing', value: summary?.fastestGrowingDatabaseName || 'No data', accent: 'yellow' }
  ], [summary]);

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Dashboard</h2>
          <p className="subtle">Latest repository forecasts across active SQL Server inventory.</p>
        </div>
        <label className="filter-control">
          <span>Risk</span>
          <select value={riskLevel} onChange={(event) => setRiskLevel(event.target.value)}>
            {riskLevels.map((level) => (
              <option key={level} value={level}>{level}</option>
            ))}
          </select>
        </label>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={false}>
        <div className="summary-grid">
          {cards.map((card) => (
            <SummaryCard key={card.label} {...card} />
          ))}
        </div>

        <div className="table-panel">
          <div className="table-panel-header">
            <h3>Database Capacity</h3>
          </div>

          <DataState isLoading={false} error="" isEmpty={databases.length === 0}>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Server</th>
                    <th>Database</th>
                    <th>Current Size GB</th>
                    <th>7-Day Growth GB</th>
                    <th>30-Day Growth GB</th>
                    <th>Growth/Day GB</th>
                    <th>Days Remaining</th>
                    <th>Risk Level</th>
                    <th>Recommendation</th>
                  </tr>
                </thead>
                <tbody>
                  {databases.map((item) => (
                    <tr
                      key={`${item.serverName}-${item.databaseName}`}
                      className="clickable-row"
                      onClick={() => navigate(`/databases/${encodeURIComponent(item.serverName)}/${encodeURIComponent(item.databaseName)}`)}
                    >
                      <td>{item.serverName}</td>
                      <td>{item.databaseName}</td>
                      <td>{formatNumber(item.currentSizeGb)}</td>
                      <td>{formatNumber(item.growth7DaysGb)}</td>
                      <td>{formatNumber(item.growth30DaysGb)}</td>
                      <td>{formatNumber(item.averageGrowthPerDayGb)}</td>
                      <td>{formatInteger(item.estimatedDaysRemaining)}</td>
                      <td><RiskBadge level={item.riskLevel} /></td>
                      <td className="recommendation-cell">{item.recommendation || '-'}</td>
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
