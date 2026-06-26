import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import SummaryCard from '../components/SummaryCard.jsx';
import { formatInteger, formatNumber } from '../components/formatters.js';
import { containsText, getUniqueOptions, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const riskLevels = ['All', 'Healthy', 'Low', 'Medium', 'High', 'Critical'];

export default function DashboardPage() {
  const navigate = useNavigate();
  const [riskLevel, setRiskLevel] = useState('All');
  const [serverFilter, setServerFilter] = useState('All');
  const [containsFilter, setContainsFilter] = useState('');
  const [sortState, setSortState] = useState({ key: 'riskLevel', direction: 'asc' });
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

  const serverOptions = useMemo(() => getUniqueOptions(databases, 'serverName'), [databases]);

  const visibleDatabases = useMemo(() => {
    const filteredRows = databases.filter((item) => {
      const matchesServer = serverFilter === 'All' || item.serverName === serverFilter;
      const matchesContains = containsText(item, [
        'serverName',
        'databaseName',
        'riskLevel',
        'recommendation'
      ], containsFilter);

      return matchesServer && matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      currentSizeGb: 'number',
      growth7DaysGb: 'number',
      growth30DaysGb: 'number',
      averageGrowthPerDayGb: 'number',
      estimatedDaysRemaining: 'number',
      riskLevel: 'risk'
    });
  }, [containsFilter, databases, serverFilter, sortState]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Dashboard</h2>
          <p className="subtle">Latest repository forecasts across active SQL Server inventory.</p>
        </div>
        <div className="toolbar-filters">
          <label className="filter-control">
            <span>Risk</span>
            <select value={riskLevel} onChange={(event) => setRiskLevel(event.target.value)}>
              {riskLevels.map((level) => (
                <option key={level} value={level}>{level}</option>
              ))}
            </select>
          </label>
        </div>
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
            <span>{formatInteger(visibleDatabases.length)} rows</span>
          </div>

          <div className="table-controls">
            <label className="search-control">
              <span>Contains</span>
              <input
                type="search"
                value={containsFilter}
                onChange={(event) => setContainsFilter(event.target.value)}
                placeholder="Server, database, risk, recommendation"
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
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleDatabases.length === 0}>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Current Size GB" sortKey="currentSizeGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="7-Day Growth GB" sortKey="growth7DaysGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="30-Day Growth GB" sortKey="growth30DaysGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Growth/Day GB" sortKey="averageGrowthPerDayGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Days Remaining" sortKey="estimatedDaysRemaining" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Risk Level" sortKey="riskLevel" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Recommendation" sortKey="recommendation" sortState={sortState} onSort={handleSort} /></th>
                  </tr>
                </thead>
                <tbody>
                  {visibleDatabases.map((item) => (
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
