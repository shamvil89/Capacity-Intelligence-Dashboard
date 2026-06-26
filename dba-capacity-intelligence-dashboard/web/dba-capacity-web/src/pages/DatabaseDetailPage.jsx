import { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from 'recharts';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SummaryCard from '../components/SummaryCard.jsx';
import { useTimezone } from '../components/TimezoneContext.jsx';
import { formatDateTime, formatNumber } from '../components/formatters.js';
import { api } from '../services/api.js';

export default function DatabaseDetailPage() {
  const { serverName = '', databaseName = '' } = useParams();
  const { effectiveTimeZone } = useTimezone();
  const [database, setDatabase] = useState(null);
  const [trend, setTrend] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const [databaseRows, trendRows] = await Promise.all([
          api.getCapacityDatabases({ serverName, databaseName }),
          api.getDatabaseTrend(serverName, databaseName, 90)
        ]);

        const exactDatabase = databaseRows.find((row) =>
          row.serverName.toLowerCase() === serverName.toLowerCase()
          && row.databaseName.toLowerCase() === databaseName.toLowerCase()
        ) ?? databaseRows[0] ?? null;

        if (isMounted) {
          setDatabase(exactDatabase);
          setTrend(trendRows);
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
  }, [serverName, databaseName]);

  const chartData = useMemo(() => trend.map((point) => ({
    ...point,
    label: formatDateTime(point.collectionTime, effectiveTimeZone)
  })), [effectiveTimeZone, trend]);

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <Link className="text-link" to="/">Back to dashboard</Link>
          <h2>{databaseName}</h2>
          <p className="subtle">{serverName}</p>
        </div>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={!database}>
        <div className="summary-grid detail-grid">
          <SummaryCard label="Current Size" value={`${formatNumber(database?.currentSizeGb)} GB`} accent="blue" />
          <SummaryCard label="30-Day Growth" value={`${formatNumber(database?.growth30DaysGb)} GB`} accent="orange" />
          <article className="summary-card accent-red">
            <span>Risk Level</span>
            <strong><RiskBadge level={database?.riskLevel} /></strong>
          </article>
          <SummaryCard label="Days Remaining" value={database?.estimatedDaysRemaining ?? 'No data'} accent="yellow" />
        </div>

        <section className="detail-section">
          <h3>Recommendation</h3>
          <p>{database?.recommendation || 'No recommendation available.'}</p>
        </section>

        <section className="chart-panel">
          <div className="table-panel-header">
            <h3>Size Trend</h3>
            <span>Last 90 days</span>
          </div>

          <DataState isLoading={false} error="" isEmpty={chartData.length === 0}>
            <div className="chart-wrap">
              <ResponsiveContainer width="100%" height={340}>
                <LineChart data={chartData} margin={{ top: 12, right: 24, bottom: 12, left: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" stroke="#d8dee6" />
                  <XAxis dataKey="label" minTickGap={32} tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Legend />
                  <Line type="monotone" dataKey="totalSizeGb" name="Total GB" stroke="#2563eb" strokeWidth={2} dot={false} />
                  <Line type="monotone" dataKey="dataSizeGb" name="Data GB" stroke="#16a34a" strokeWidth={2} dot={false} />
                  <Line type="monotone" dataKey="logSizeGb" name="Log GB" stroke="#f97316" strokeWidth={2} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </DataState>
        </section>
      </DataState>
    </section>
  );
}
