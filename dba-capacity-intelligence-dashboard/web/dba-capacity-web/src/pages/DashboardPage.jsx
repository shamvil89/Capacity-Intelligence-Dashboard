import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import ColumnFilter from '../components/ColumnFilter.jsx';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import SummaryCard from '../components/SummaryCard.jsx';
import { formatInteger, formatRemainingTimeFromDays, formatStorageFromGb } from '../components/formatters.js';
import { containsText, getSelectedFilterFields, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const riskLevels = ['All', 'Healthy', 'Low', 'Medium', 'High', 'Critical'];
const environmentOptions = ['All', 'Development', 'Test', 'QA', 'UAT', 'Production', 'DR'];
const databaseFilterColumns = [
  { key: 'environment', label: 'Environment' },
  { key: 'serverName', label: 'Server' },
  { key: 'databaseName', label: 'Database' },
  { key: 'riskLevel', label: 'Risk' },
  { key: 'recommendation', label: 'Recommendation' }
];

export default function DashboardPage() {
  const navigate = useNavigate();
  const [riskLevel, setRiskLevel] = useState('All');
  const [environmentFilter, setEnvironmentFilter] = useState('All');
  const [containsFilter, setContainsFilter] = useState('');
  const [filterColumns, setFilterColumns] = useState(databaseFilterColumns.map((column) => column.key));
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
          api.getSummary({ riskLevel, environment: environmentFilter }),
          api.getCapacityDatabases({ riskLevel, environment: environmentFilter })
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
  }, [environmentFilter, riskLevel]);

  const cards = useMemo(() => [
    { label: 'Total Servers', value: formatInteger(summary?.totalServers), accent: 'teal' },
    { label: 'Total Databases', value: formatInteger(summary?.totalDatabases), accent: 'green' },
    { label: 'Critical Alerts', value: formatInteger(summary?.criticalAlerts), accent: 'red' },
    { label: 'High Risk Databases', value: formatInteger(summary?.highRiskDatabases), accent: 'orange' },
    { label: 'Largest Database', value: summary?.largestDatabaseName || 'No data', accent: 'blue' },
    { label: 'Fastest Growing', value: summary?.fastestGrowingDatabaseName || 'No data', accent: 'yellow' }
  ], [summary]);

  const visibleDatabases = useMemo(() => {
    const activeFilterFields = getSelectedFilterFields(databaseFilterColumns, filterColumns);
    const filteredRows = databases.filter((item) => {
      const matchesContains = containsText(item, activeFilterFields, containsFilter);

      return matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      currentSizeGb: 'number',
      growth7DaysGb: 'number',
      growth30DaysGb: 'number',
      averageGrowthPerDayGb: 'number',
      estimatedDaysRemaining: 'number',
      riskLevel: 'risk'
    });
  }, [containsFilter, databases, filterColumns, sortState]);

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
          <label className="filter-control">
            <span>Environment</span>
            <select value={environmentFilter} onChange={(event) => setEnvironmentFilter(event.target.value)}>
              {environmentOptions.map((environment) => (
                <option key={environment} value={environment}>{environment}</option>
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
            <ColumnFilter
              columns={databaseFilterColumns}
              selectedColumns={filterColumns}
              value={containsFilter}
              onChange={setContainsFilter}
              onSelectedColumnsChange={setFilterColumns}
              placeholder="Environment, server, database, risk, recommendation"
            />
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleDatabases.length === 0}>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th><SortableHeader label="Environment" sortKey="environment" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Current Size" sortKey="currentSizeGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="7-Day Growth" sortKey="growth7DaysGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="30-Day Growth" sortKey="growth30DaysGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Growth/Day" sortKey="averageGrowthPerDayGb" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Time Remaining" sortKey="estimatedDaysRemaining" sortState={sortState} onSort={handleSort} /></th>
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
                      <td>{item.environment || '-'}</td>
                      <td>{item.serverName}</td>
                      <td>{item.databaseName}</td>
                      <td>{formatStorageFromGb(item.currentSizeGb)}</td>
                      <td>{formatStorageFromGb(item.growth7DaysGb)}</td>
                      <td>{formatStorageFromGb(item.growth30DaysGb)}</td>
                      <td>{formatStorageFromGb(item.averageGrowthPerDayGb)}</td>
                      <td>{formatRemainingTimeFromDays(item.estimatedDaysRemaining)}</td>
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
