export function formatNumber(value, fractionDigits = 2) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return Number(value).toLocaleString(undefined, {
    maximumFractionDigits: fractionDigits,
    minimumFractionDigits: fractionDigits
  });
}

export function formatInteger(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return Number(value).toLocaleString();
}

export function parseRepositoryDateTime(value) {
  if (value instanceof Date) {
    return value;
  }

  if (typeof value === 'string') {
    const trimmedValue = value.trim();
    const hasTime = /^\d{4}-\d{2}-\d{2}T/.test(trimmedValue);
    const hasTimeZone = /(Z|[+-]\d{2}:?\d{2})$/i.test(trimmedValue);

    if (hasTime && !hasTimeZone) {
      return new Date(`${trimmedValue}Z`);
    }
  }

  return new Date(value);
}

export function formatDateTime(value, timeZone) {
  if (!value) {
    return '-';
  }

  const parsedDate = parseRepositoryDateTime(value);

  if (Number.isNaN(parsedDate.getTime())) {
    return '-';
  }

  const options = {
    dateStyle: 'medium',
    timeStyle: 'short'
  };

  if (timeZone) {
    options.timeZone = timeZone;
  }

  try {
    return new Intl.DateTimeFormat(undefined, options).format(parsedDate);
  } catch {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short'
    }).format(parsedDate);
  }
}
