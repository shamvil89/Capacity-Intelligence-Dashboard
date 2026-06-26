export default function DataState({ isLoading, error, isEmpty, children }) {
  if (isLoading) {
    return <div className="state-box">Loading data...</div>;
  }

  if (error) {
    return <div className="state-box error-box">{error}</div>;
  }

  if (isEmpty) {
    return <div className="state-box">No data available.</div>;
  }

  return children;
}
