export default function SummaryCard({ label, value, accent = 'neutral' }) {
  return (
    <article className={`summary-card accent-${accent}`}>
      <span>{label}</span>
      <strong>{value ?? 'No data'}</strong>
    </article>
  );
}
