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

export function formatStorageFromGb(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  const numericValue = Number(value);
  const absoluteValue = Math.abs(numericValue);

  if (absoluteValue < 1) {
    const mbValue = numericValue * 1024;
    return `${mbValue.toLocaleString(undefined, {
      maximumFractionDigits: Math.abs(mbValue) >= 10 ? 1 : 2,
      minimumFractionDigits: 0
    })} MB`;
  }

  return `${numericValue.toLocaleString(undefined, {
    maximumFractionDigits: 2,
    minimumFractionDigits: 0
  })} GB`;
}

export function formatRemainingTimeFromDays(value, emptyValue = '-') {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return emptyValue;
  }

  const numericValue = Number(value);

  if (numericValue < 1) {
    const hours = numericValue * 24;

    if (hours < 1) {
      return '<1 hour';
    }

    const roundedHours = Math.max(1, Math.round(hours));
    return `${roundedHours.toLocaleString()} ${roundedHours === 1 ? 'hour' : 'hours'}`;
  }

  const formattedDays = numericValue.toLocaleString(undefined, {
    maximumFractionDigits: numericValue < 10 ? 1 : 0,
    minimumFractionDigits: 0
  });

  return `${formattedDays} ${Math.round(numericValue * 10) / 10 === 1 ? 'day' : 'days'}`;
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
