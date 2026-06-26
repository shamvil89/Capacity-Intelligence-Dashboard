import { ArrowDown, ArrowUp, ArrowUpDown } from 'lucide-react';

export default function SortableHeader({ label, sortKey, sortState, onSort }) {
  const isActive = sortState.key === sortKey;
  const Icon = isActive ? (sortState.direction === 'asc' ? ArrowUp : ArrowDown) : ArrowUpDown;

  return (
    <button
      type="button"
      className={`sort-header ${isActive ? 'active' : ''}`}
      onClick={() => onSort(sortKey)}
    >
      <span>{label}</span>
      <Icon aria-hidden="true" size={14} />
    </button>
  );
}
