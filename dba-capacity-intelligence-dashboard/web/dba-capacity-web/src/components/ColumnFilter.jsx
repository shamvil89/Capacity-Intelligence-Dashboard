export default function ColumnFilter({
  columns,
  placeholder,
  selectedColumns = [],
  value,
  onChange,
  onSelectedColumnsChange
}) {
  const activeColumns = selectedColumns.length > 0 ? selectedColumns : columns.map((column) => column.key);
  const activeColumnSet = new Set(activeColumns);

  function handleColumnToggle(columnKey) {
    const nextColumns = activeColumnSet.has(columnKey)
      ? activeColumns.filter((key) => key !== columnKey)
      : [...activeColumns, columnKey];

    onSelectedColumnsChange(nextColumns.length > 0 ? nextColumns : columns.map((column) => column.key));
  }

  return (
    <div className="column-filter">
      <label className="search-control column-filter-search">
        <span>Contains</span>
        <input
          type="search"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
        />
      </label>

      <div className="column-filter-options" role="group" aria-label="Filter columns">
        {columns.map((column) => (
          <button
            type="button"
            key={column.key}
            className={activeColumnSet.has(column.key) ? 'filter-chip active' : 'filter-chip'}
            aria-pressed={activeColumnSet.has(column.key)}
            onClick={() => handleColumnToggle(column.key)}
          >
            {column.label}
          </button>
        ))}
      </div>
    </div>
  );
}
