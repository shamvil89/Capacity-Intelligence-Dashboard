import { createContext, useCallback, useContext, useMemo, useState } from 'react';

const STORAGE_KEY = 'dba-capacity-time-zone';
const LOCAL_TIME_ZONE = 'local';

const PRIORITY_TIME_ZONES = [
  'UTC',
  'Asia/Calcutta',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Asia/Dubai',
  'Asia/Singapore',
  'Australia/Sydney'
];

const TimezoneContext = createContext(null);

function getBrowserTimeZone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}

function getSupportedTimeZones() {
  if (typeof Intl.supportedValuesOf === 'function') {
    return Intl.supportedValuesOf('timeZone');
  }

  return Array.from(new Set([getBrowserTimeZone(), ...PRIORITY_TIME_ZONES]));
}

function getOffsetLabel(timeZone) {
  try {
    const offsetPart = new Intl.DateTimeFormat(undefined, {
      timeZone,
      timeZoneName: 'shortOffset'
    }).formatToParts(new Date()).find((part) => part.type === 'timeZoneName');

    return offsetPart?.value ?? '';
  } catch {
    return '';
  }
}

function formatTimeZoneLabel(timeZone) {
  const offset = getOffsetLabel(timeZone);
  const label = timeZone.replaceAll('_', ' ');
  return offset ? `${label} (${offset})` : label;
}

function getStoredTimeZone() {
  const supportedTimeZones = getSupportedTimeZones();

  try {
    const storedValue = window.localStorage.getItem(STORAGE_KEY);
    if (storedValue === LOCAL_TIME_ZONE || supportedTimeZones.includes(storedValue)) {
      return storedValue;
    }
  } catch {
    // Ignore storage access errors and keep the UI usable with local time.
  }

  return LOCAL_TIME_ZONE;
}

function buildTimeZoneOptions() {
  const browserTimeZone = getBrowserTimeZone();
  const supportedTimeZones = getSupportedTimeZones();
  const prioritized = PRIORITY_TIME_ZONES.filter((timeZone) => supportedTimeZones.includes(timeZone));
  const remaining = supportedTimeZones.filter((timeZone) => !prioritized.includes(timeZone));

  return [
    {
      value: LOCAL_TIME_ZONE,
      label: `Browser local (${formatTimeZoneLabel(browserTimeZone)})`
    },
    ...prioritized.map((timeZone) => ({
      value: timeZone,
      label: formatTimeZoneLabel(timeZone)
    })),
    ...remaining.map((timeZone) => ({
      value: timeZone,
      label: formatTimeZoneLabel(timeZone)
    }))
  ];
}

export function TimezoneProvider({ children }) {
  const [timeZone, setTimeZoneValue] = useState(getStoredTimeZone);
  const timeZoneOptions = useMemo(() => buildTimeZoneOptions(), []);
  const effectiveTimeZone = timeZone === LOCAL_TIME_ZONE ? undefined : timeZone;

  const setTimeZone = useCallback((nextTimeZone) => {
    setTimeZoneValue(nextTimeZone);

    try {
      window.localStorage.setItem(STORAGE_KEY, nextTimeZone);
    } catch {
      // Persisting the preference is helpful, not required.
    }
  }, []);

  const contextValue = useMemo(() => ({
    effectiveTimeZone,
    setTimeZone,
    timeZone,
    timeZoneOptions
  }), [effectiveTimeZone, setTimeZone, timeZone, timeZoneOptions]);

  return (
    <TimezoneContext.Provider value={contextValue}>
      {children}
    </TimezoneContext.Provider>
  );
}

export function useTimezone() {
  const contextValue = useContext(TimezoneContext);

  if (!contextValue) {
    throw new Error('useTimezone must be used inside TimezoneProvider.');
  }

  return contextValue;
}
