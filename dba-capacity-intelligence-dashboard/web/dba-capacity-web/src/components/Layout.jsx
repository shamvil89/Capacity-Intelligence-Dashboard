import { Activity, AlertTriangle, Database, Gauge, TableProperties } from 'lucide-react';
import { NavLink, Outlet } from 'react-router-dom';

const navItems = [
  { to: '/', label: 'Dashboard', icon: Gauge },
  { to: '/top-growing-tables', label: 'Top Tables', icon: TableProperties },
  { to: '/alerts', label: 'Alerts', icon: AlertTriangle }
];

export default function Layout() {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <Database aria-hidden="true" size={24} />
          <div>
            <strong>DBA Capacity</strong>
            <span>Intelligence</span>
          </div>
        </div>

        <nav className="nav-list" aria-label="Main navigation">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink key={item.to} to={item.to} end={item.to === '/'} className="nav-link">
                <Icon aria-hidden="true" size={18} />
                <span>{item.label}</span>
              </NavLink>
            );
          })}
        </nav>
      </aside>

      <div className="content-shell">
        <header className="top-header">
          <div>
            <p className="eyebrow">DBAUtility repository</p>
            <h1>Capacity Intelligence Dashboard</h1>
          </div>
          <div className="header-status">
            <Activity aria-hidden="true" size={18} />
            <span>Repository read-only API</span>
          </div>
        </header>

        <main className="main-content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
