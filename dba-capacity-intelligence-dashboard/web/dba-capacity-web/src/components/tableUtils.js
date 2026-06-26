export function containsText(row, fields, searchText) {
  const normalizedSearch = normalize(searchText);

  if (!normalizedSearch) {
    return true;
  }

  return fields.some((field) => normalize(resolveValue(row, field)).includes(normalizedSearch));
}

export function getUniqueOptions(rows, field) {
  return [...new Set(rows.map((row) => resolveValue(row, field)).filter((value) => value !== null && value !== undefined && value !== ''))]
    .sort((left, right) => String(left).localeCompare(String(right)));
}

export function sortRows(rows, sortState, columnTypes = {}) {
  if (!sortState.key) {
    return rows;
  }

  const direction = sortState.direction === 'asc' ? 1 : -1;
  const type = columnTypes[sortState.key] ?? 'text';

  return [...rows].sort((left, right) => compareValues(
    resolveValue(left, sortState.key),
    resolveValue(right, sortState.key),
    type
  ) * direction);
}

export function nextSortState(currentState, key) {
  if (currentState.key !== key) {
    return { key, direction: 'asc' };
  }

  return {
    key,
    direction: currentState.direction === 'asc' ? 'desc' : 'asc'
  };
}

function compareValues(left, right, type) {
  const leftEmpty = left === null || left === undefined || left === '';
  const rightEmpty = right === null || right === undefined || right === '';

  if (leftEmpty && rightEmpty) {
    return 0;
  }

  if (leftEmpty) {
    return 1;
  }

  if (rightEmpty) {
    return -1;
  }

  if (type === 'number') {
    return Number(left) - Number(right);
  }

  if (type === 'date') {
    return new Date(left).getTime() - new Date(right).getTime();
  }

  if (type === 'risk') {
    return riskRank(left) - riskRank(right);
  }

  return String(left).localeCompare(String(right), undefined, { sensitivity: 'base', numeric: true });
}

function resolveValue(row, field) {
  if (typeof field === 'function') {
    return field(row);
  }

  return row[field];
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function riskRank(value) {
  const ranks = {
    healthy: 1,
    low: 2,
    medium: 3,
    high: 4,
    critical: 5
  };

  return ranks[normalize(value)] ?? 99;
}
