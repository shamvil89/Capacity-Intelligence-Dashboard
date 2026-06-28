import { useEffect, useMemo, useState } from 'react';
import ColumnFilter from '../components/ColumnFilter.jsx';
import DataState from '../components/DataState.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { formatInteger, formatNumber } from '../components/formatters.js';
import { containsText, getSelectedFilterFields, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const tableFilterColumns = [
  { key: 'environment', label: 'Environment' },
  { key: 'serverName', label: 'Server' },
  { key: 'databaseName', label: 'Database' },
  { key: 'schemaName', label: 'Schema' },
  { key: 'tableName', label: 'Table' }
];

export default function TopGrowingTablesPage() {
  const [tables, setTables] = useState([]);
  const [containsFilter, setContainsFilter] = useState('');
  const [filterColumns, setFilterColumns] = useState(tableFilterColumns.map((column) => column.key));
  const [sortState, setSortState] = useState({ key: 'growth30DaysMb', direction: 'desc' });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = await api.getTopGrowingTables(500);
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
  }, []);

  const visibleTables = useMemo(() => {
    const activeFilterFields = getSelectedFilterFields(tableFilterColumns, filterColumns);
    const filteredRows = tables.filter((item) => {
      const matchesContains = containsText(item, activeFilterFields, containsFilter);

      return matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      currentSizeMb: 'number',
      growth30DaysMb: 'number',
      currentRowCount: 'number',
      rowGrowth30Days: 'number'
    });
  }, [containsFilter, filterColumns, sortState, tables]);

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
            <ColumnFilter
              columns={tableFilterColumns}
              selectedColumns={filterColumns}
              value={containsFilter}
              onChange={setContainsFilter}
              onSelectedColumnsChange={setFilterColumns}
              placeholder="Environment, server, database, schema, table"
            />
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
