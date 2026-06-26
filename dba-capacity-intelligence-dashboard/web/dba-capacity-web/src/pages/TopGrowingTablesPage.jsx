import { useEffect, useState } from 'react';
import DataState from '../components/DataState.jsx';
import { formatInteger, formatNumber } from '../components/formatters.js';
import { api } from '../services/api.js';

export default function TopGrowingTablesPage() {
  const [tables, setTables] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = await api.getTopGrowingTables(20);
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
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Server</th>
                  <th>Database</th>
                  <th>Schema</th>
                  <th>Table</th>
                  <th>Current Size MB</th>
                  <th>30-Day Growth MB</th>
                  <th>Current Row Count</th>
                  <th>Row Growth</th>
                </tr>
              </thead>
              <tbody>
                {tables.map((item) => (
                  <tr key={`${item.serverName}-${item.databaseName}-${item.schemaName}-${item.tableName}`}>
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
        </div>
      </DataState>
    </section>
  );
}
