export default function RiskBadge({ level }) {
  const normalized = (level || 'Healthy').toLowerCase();
  return <span className={`risk-badge risk-${normalized}`}>{level || 'Healthy'}</span>;
}
