import { useEffect, useMemo, useState } from 'react';
import DataState from '../components/DataState.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { formatInteger, formatNumber } from '../components/formatters.js';
import { containsText, getUniqueOptions, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const environmentOptions = ['All', 'Development', 'Test', 'QA', 'UAT', 'Production', 'DR'];

export default function TopGrowingTablesPage() {
  const [tables, setTables] = useState([]);
  const [containsFilter, setContainsFilter] = useState('');
  const [environmentFilter, setEnvironmentFilter] = useState('All');
  const [serverFilter, setServerFilter] = useState('All');
  const [databaseFilter, setDatabaseFilter] = useState('All');
  const [schemaFilter, setSchemaFilter] = useState('All');
  const [sortState, setSortState] = useState({ key: 'growth30DaysMb', direction: 'desc' });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = await api.getTopGrowingTables(500, { environment: environmentFilter });
        if (isMounted) {
          setTables(rows);
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
  }, [environmentFilter]);

  const serverOptions = useMemo(() => getUniqueOptions(tables, 'serverName'), [tables]);
  const databaseOptions = useMemo(() => getUniqueOptions(tables, 'databaseName'), [tables]);
  const schemaOptions = useMemo(() => getUniqueOptions(tables, 'schemaName'), [tables]);

  const visibleTables = useMemo(() => {
    const filteredRows = tables.filter((item) => {
      const matchesServer = serverFilter === 'All' || item.serverName === serverFilter;
      const matchesDatabase = databaseFilter === 'All' || item.databaseName === databaseFilter;
      const matchesSchema = schemaFilter === 'All' || item.schemaName === schemaFilter;
      const matchesContains = containsText(item, [
        'environment',
        'serverName',
        'databaseName',
        'schemaName',
        'tableName'
      ], containsFilter);

      return matchesServer && matchesDatabase && matchesSchema && matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      currentSizeMb: 'number',
      growth30DaysMb: 'number',
      currentRowCount: 'number',
      rowGrowth30Days: 'number'
    });
  }, [containsFilter, databaseFilter, schemaFilter, serverFilter, sortState, tables]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Top Growing Tables</h2>
          <p className="subtle">Latest table footprint with 30-day growth deltas.</p>
        </div>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={tables.length === 0}>
        <div className="table-panel">
          <div className="table-panel-header">
            <h3>Table Growth</h3>
            <span>{formatInteger(visibleTables.length)} rows</span>
          </div>

          <div className="table-controls">
            <label className="search-control">
              <span>Contains</span>
              <input
                type="search"
                value={containsFilter}
                onChange={(event) => setContainsFilter(event.target.value)}
                placeholder="Environment, server, database, schema, table"
              />
            </label>

            <label className="filter-control">
              <span>Environment</span>
              <select value={environmentFilter} onChange={(event) => setEnvironmentFilter(event.target.value)}>
                {environmentOptions.map((environment) => (
                  <option key={environment} value={environment}>{environment}</option>
                ))}
              </select>
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
              <span>Database</span>
              <select value={databaseFilter} onChange={(event) => setDatabaseFilter(event.target.value)}>
                <option value="All">All</option>
                {databaseOptions.map((databaseName) => (
                  <option key={databaseName} value={databaseName}>{databaseName}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Schema</span>
              <select value={schemaFilter} onChange={(event) => setSchemaFilter(event.target.value)}>
                <option value="All">All</option>
                {schemaOptions.map((schemaName) => (
                  <option key={schemaName} value={schemaName}>{schemaName}</option>
                ))}
              </select>
            </label>
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleTables.length === 0}>
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th><SortableHeader label="Environment" sortKey="environment" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Schema" sortKey="schemaName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Table" sortKey="tableName" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Current Size MB" sortKey="currentSizeMb" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="30-Day Growth MB" sortKey="growth30DaysMb" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Current Row Count" sortKey="currentRowCount" sortState={sortState} onSort={handleSort} /></th>
                  <th><SortableHeader label="Row Growth" sortKey="rowGrowth30Days" sortState={sortState} onSort={handleSort} /></th>
                </tr>
              </thead>
              <tbody>
                {visibleTables.map((item) => (
                  <tr key={`${item.serverName}-${item.databaseName}-${item.schemaName}-${item.tableName}`}>
                    <td>{item.environment || '-'}</td>
                    <td>{item.serverName}</td>
                    <td>{item.databaseName}</td>
                    <td>{item.schemaName}</td>
                    <td>{item.tableName}</td>
                    <td>{formatNumber(item.currentSizeMb)}</td>
                    <td>{formatNumber(item.growth30DaysMb)}</td>
                    <td>{formatInteger(item.currentRowCount)}</td>
                    <td>{formatInteger(item.rowGrowth30Days)}</td>
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
