import { lazy, Suspense } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import Layout from './components/Layout.jsx';

const DashboardPage = lazy(() => import('./pages/DashboardPage.jsx'));
const DatabaseDetailPage = lazy(() => import('./pages/DatabaseDetailPage.jsx'));
const TopGrowingTablesPage = lazy(() => import('./pages/TopGrowingTablesPage.jsx'));
const AlertsPage = lazy(() => import('./pages/AlertsPage.jsx'));

export default function App() {
  return (
    <Suspense fallback={<div className="route-loading">Loading view...</div>}>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/databases/:serverName/:databaseName" element={<DatabaseDetailPage />} />
          <Route path="/top-growing-tables" element={<TopGrowingTablesPage />} />
          <Route path="/alerts" element={<AlertsPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  );
}
