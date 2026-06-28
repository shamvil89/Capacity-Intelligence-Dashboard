import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronRight, Info, X } from 'lucide-react';
import queryPlanScript from 'html-query-plan/dist/qp.js?raw';
import 'html-query-plan/css/qp.css';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { useTimezone } from '../components/TimezoneContext.jsx';
import { formatDateTime } from '../components/formatters.js';
import { containsText, getUniqueOptions, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const environmentOptions = ['All', 'Development', 'Test', 'QA', 'UAT', 'Production', 'DR'];
let queryPlanRendererPromise;

export default function AlertsPage() {
  const { effectiveTimeZone } = useTimezone();
  const [alerts, setAlerts] = useState([]);
  const [selectedAlert, setSelectedAlert] = useState(null);
  const [containsFilter, setContainsFilter] = useState('');
  const [environmentFilter, setEnvironmentFilter] = useState('All');
  const [serverFilter, setServerFilter] = useState('All');
  const [severityFilter, setSeverityFilter] = useState('All');
  const [alertTypeFilter, setAlertTypeFilter] = useState('All');
  const [sortState, setSortState] = useState({ key: 'alertTime', direction: 'desc' });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = await api.getActiveAlerts();
        if (isMounted) {
          setAlerts(rows);
        }
      } catch (err) {
        if (isMounted) {
          setError(err.message);
        }
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    load();
    return () => {
      isMounted = false;
    };
  }, []);

  const serverOptions = useMemo(() => getUniqueOptions(alerts, 'serverName'), [alerts]);
  const severityOptions = useMemo(() => getUniqueOptions(alerts, 'severity'), [alerts]);
  const alertTypeOptions = useMemo(() => getUniqueOptions(alerts, 'alertType'), [alerts]);

  const visibleAlerts = useMemo(() => {
    const filteredRows = alerts.filter((item) => {
      const matchesEnvironment = environmentFilter === 'All' || item.environment === environmentFilter;
      const matchesServer = serverFilter === 'All' || item.serverName === serverFilter;
      const matchesSeverity = severityFilter === 'All' || item.severity === severityFilter;
      const matchesAlertType = alertTypeFilter === 'All' || item.alertType === alertTypeFilter;
      const matchesContains = containsText(item, [
        'environment',
        'serverName',
        'databaseName',
        'alertType',
        'severity',
        'message',
        'sourceScript',
        'detailsJson'
      ], containsFilter);

      return matchesEnvironment && matchesServer && matchesSeverity && matchesAlertType && matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      alertTime: 'date',
      severity: 'risk'
    });
  }, [alertTypeFilter, alerts, containsFilter, environmentFilter, serverFilter, severityFilter, sortState]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>Active Alerts</h2>
          <p className="subtle">Unresolved repository alerts from forecast and collector runs.</p>
        </div>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={alerts.length === 0}>
        <div className="table-panel alerts-panel">
          <div className="table-panel-header">
            <h3>Alert Queue</h3>
            <span>{visibleAlerts.length} rows</span>
          </div>

          <div className="table-controls alerts-controls">
            <label className="search-control">
              <span>Contains</span>
              <input
                type="search"
                value={containsFilter}
                onChange={(event) => setContainsFilter(event.target.value)}
                placeholder="Environment, server, database, type, message"
              />
            </label>

            <label className="filter-control">
              <span>Environment</span>
              <select value={environmentFilter} onChange={(event) => setEnvironmentFilter(event.target.value)}>
                {environmentOptions.map((environment) => (
                  <option key={environment} value={environment}>{environment}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Server</span>
              <select value={serverFilter} onChange={(event) => setServerFilter(event.target.value)}>
                <option value="All">All</option>
                {serverOptions.map((serverName) => (
                  <option key={serverName} value={serverName}>{serverName}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Severity</span>
              <select value={severityFilter} onChange={(event) => setSeverityFilter(event.target.value)}>
                <option value="All">All</option>
                {severityOptions.map((severity) => (
                  <option key={severity} value={severity}>{severity}</option>
                ))}
              </select>
            </label>

            <label className="filter-control">
              <span>Type</span>
              <select value={alertTypeFilter} onChange={(event) => setAlertTypeFilter(event.target.value)}>
                <option value="All">All</option>
                {alertTypeOptions.map((alertType) => (
                  <option key={alertType} value={alertType}>{alertType}</option>
                ))}
              </select>
            </label>
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleAlerts.length === 0}>
            <div className="table-scroll">
              <table className="alerts-table">
                <thead>
                  <tr>
                    <th><SortableHeader label="Time" sortKey="alertTime" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Environment" sortKey="environment" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Alert Type" sortKey="alertType" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Severity" sortKey="severity" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Message" sortKey="message" sortState={sortState} onSort={handleSort} /></th>
                    <th>More Info</th>
                  </tr>
                </thead>
                <tbody>
                  {visibleAlerts.map((item) => (
                    <tr key={item.alertId ?? `${item.alertTime}-${item.serverName}-${item.alertType}`}>
                      <td>{formatDateTime(item.alertTime, effectiveTimeZone)}</td>
                      <td>{item.environment || '-'}</td>
                      <td>{item.serverName}</td>
                      <td>{item.databaseName || '-'}</td>
                      <td>{item.alertType}</td>
                      <td><RiskBadge level={item.severity} /></td>
                      <td className="recommendation-cell alert-message-cell">{item.message}</td>
                      <td>
                        <button type="button" className="secondary-action" onClick={() => setSelectedAlert(item)}>
                          <Info aria-hidden="true" size={14} />
                          More info
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </DataState>
        </div>
      </DataState>

      {selectedAlert ? (
        <AlertDetailsModal
          alert={selectedAlert}
          effectiveTimeZone={effectiveTimeZone}
          onClose={() => setSelectedAlert(null)}
        />
      ) : null}
    </section>
  );
}

function AlertDetailsModal({ alert, effectiveTimeZone, onClose }) {
  const details = useMemo(() => parseAlertDetails(alert.detailsJson), [alert.detailsJson]);
  const hasDedicatedEvidence = useMemo(() => hasBlockingEvidence(details), [details]);
  const evidenceDetails = useMemo(() => {
    const cleanedDetails = stripQueryPlanXml(details);
    return hasDedicatedEvidence ? stripDedicatedEvidence(cleanedDetails) : cleanedDetails;
  }, [details, hasDedicatedEvidence]);

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="modal-panel" role="dialog" aria-modal="true" aria-labelledby="alert-details-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <div>
            <p className="eyebrow">Alert evidence</p>
            <h3 id="alert-details-title">{alert.alertType}</h3>
          </div>
          <button type="button" className="icon-action" aria-label="Close details" onClick={onClose}>
            <X aria-hidden="true" size={18} />
          </button>
        </div>

        <div className="modal-body">
          <div className="detail-summary-grid">
            <DetailItem label="Time" value={formatDateTime(alert.alertTime, effectiveTimeZone)} />
            <DetailItem label="Environment" value={alert.environment || '-'} />
            <DetailItem label="Server" value={alert.serverName} />
            <DetailItem label="Database" value={alert.databaseName || '-'} />
            <DetailItem label="Severity" value={alert.severity} />
            <DetailItem label="Source" value={alert.sourceScript || details?.sourceScripts || '-'} wide />
          </div>

          <section className="modal-section">
            <h4>Message</h4>
            <p>{alert.message}</p>
          </section>

          <BlockingEvidenceSection details={details} />

          <QueryPlanSection alertType={alert.alertType} sourceScript={alert.sourceScript} details={details} />

          <section className="modal-section">
            <h4>Evidence</h4>
            {hasRenderableDetail(evidenceDetails) ? (
              <StructuredDetails value={evidenceDetails} />
            ) : (
              <p>No additional structured details were stored for this alert.</p>
            )}
          </section>
        </div>
      </section>
    </div>
  );
}

function BlockingEvidenceSection({ details }) {
  const heldLocks = normalizeEvidenceList(details?.leadBlockerHeldLocks);
  const blockedSessions = normalizeEvidenceList(details?.blockedSessions);
  const blockingEvidence = normalizeEvidenceList(details?.blockingEvidence);
  const lockContext = getBlockingContext(details);

  if (heldLocks.length === 0 && blockedSessions.length === 0 && blockingEvidence.length === 0 && !lockContext) {
    return null;
  }

  return (
    <>
      {lockContext ? (
        <CollapsibleSection
          title="Lock / Blocking Context"
          summary={details?.blockingSessionId ? `Blocked by session ${details.blockingSessionId}` : 'Session context'}
        >
          <StructuredDetails value={lockContext} />
          {heldLocks.length === 0 && blockedSessions.length === 0 && blockingEvidence.length === 0 ? (
            <div className="query-plan-empty">
              No lock graph rows were captured for this alert. BlockingChain alerts include lead blocker locks and blocked sessions when the blocking collector finds an active chain.
            </div>
          ) : null}
        </CollapsibleSection>
      ) : null}

      {heldLocks.length > 0 ? (
        <CollapsibleSection title="Lead Blocker Held Locks" summary={`${heldLocks.length} lock${heldLocks.length === 1 ? '' : 's'}`}>
          <div className="evidence-table-scroll">
            <table className="evidence-mini-table">
              <thead>
                <tr>
                  <th>Database</th>
                  <th>Object</th>
                  <th>Resource</th>
                  <th>Mode</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {heldLocks.map((lock, index) => (
                  <tr key={`${lock.databaseName}-${lock.objectName}-${lock.lockMode}-${index}`}>
                    <td>{formatDetailValue(lock.databaseName)}</td>
                    <td>{formatDetailValue(lock.objectName)}</td>
                    <td>{formatDetailValue(lock.resourceType)}</td>
                    <td>{formatDetailValue(lock.lockMode)}</td>
                    <td>{formatDetailValue(lock.lockStatus)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CollapsibleSection>
      ) : null}

      {blockedSessions.length > 0 ? (
        <CollapsibleSection title="Blocked Sessions" summary={`${blockedSessions.length} session${blockedSessions.length === 1 ? '' : 's'}`}>
          <div className="evidence-table-scroll">
            <table className="evidence-mini-table">
              <thead>
                <tr>
                  <th>Session</th>
                  <th>Database</th>
                  <th>Login</th>
                  <th>Wait</th>
                  <th>Wait ms</th>
                  <th>Blocked Object</th>
                  <th>Lock Mode</th>
                </tr>
              </thead>
              <tbody>
                {blockedSessions.map((session, index) => (
                  <tr key={`${session.blockedSessionId}-${session.waitResource}-${index}`}>
                    <td>{formatDetailValue(session.blockedSessionId)}</td>
                    <td>{formatDetailValue(session.databaseName)}</td>
                    <td>{formatDetailValue(session.loginName)}</td>
                    <td>{formatDetailValue(session.waitType)}</td>
                    <td>{formatDetailValue(session.waitDurationMs)}</td>
                    <td>{formatDetailValue(session.blockedObjectName)}</td>
                    <td>{formatDetailValue(session.blockedLockMode)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CollapsibleSection>
      ) : null}

      {blockingEvidence.length > 0 ? (
        <CollapsibleSection title="Blocking Evidence" summary={`${blockingEvidence.length} row${blockingEvidence.length === 1 ? '' : 's'}`}>
          <div className="evidence-table-scroll">
            <table className="evidence-mini-table">
              <thead>
                <tr>
                  <th>Lead Blocker</th>
                  <th>Blocked Session</th>
                  <th>Wait</th>
                  <th>Wait ms</th>
                  <th>Blocked Object</th>
                  <th>Login</th>
                </tr>
              </thead>
              <tbody>
                {blockingEvidence.map((item, index) => (
                  <tr key={`${item.leadBlockerSessionId}-${item.blockedSessionId}-${index}`}>
                    <td>{formatDetailValue(item.leadBlockerSessionId)}</td>
                    <td>{formatDetailValue(item.blockedSessionId)}</td>
                    <td>{formatDetailValue(item.waitType)}</td>
                    <td>{formatDetailValue(item.waitDurationMs)}</td>
                    <td>{formatDetailValue(item.blockedObjectName)}</td>
                    <td>{formatDetailValue(item.leadBlockerLoginName)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CollapsibleSection>
      ) : null}
    </>
  );
}

function QueryPlanSection({ alertType, sourceScript, details }) {
  const containerRef = useRef(null);
  const planEntries = useMemo(() => collectQueryPlans(details), [details]);
  const isPlanAwareAlert = isPlanAwareAlertType(alertType, details?.category, sourceScript, details?.sourceScripts);
  const [isOpen, setIsOpen] = useState(() => planEntries.length > 0);
  const [selectedPlanIndex, setSelectedPlanIndex] = useState(0);
  const selectedPlan = planEntries[Math.min(selectedPlanIndex, Math.max(planEntries.length - 1, 0))];

  useEffect(() => {
    setSelectedPlanIndex(0);
    setIsOpen(planEntries.length > 0);
  }, [planEntries.length]);

  useEffect(() => {
    const container = containerRef.current;
    let isCancelled = false;

    if (!isOpen || !container || !selectedPlan) {
      return undefined;
    }

    container.innerHTML = '';
    container.textContent = 'Loading query plan...';

    loadQueryPlanRenderer()
      .then((renderer) => {
        if (isCancelled) {
          return;
        }

        container.innerHTML = '';
        renderer.showPlan(container, selectedPlan.planXml, { jsTooltips: true });
      })
      .catch((err) => {
        if (!isCancelled) {
          container.textContent = `Could not render query plan: ${err.message}`;
        }
      });

    return () => {
      isCancelled = true;
      container.innerHTML = '';
    };
  }, [isOpen, selectedPlan]);

  if (planEntries.length === 0 && !isPlanAwareAlert) {
    return null;
  }

  if (planEntries.length === 0) {
    return (
      <CollapsibleSection
        title="Query Plan"
        summary="No cached plan"
        className="query-plan-section"
        isOpen={isOpen}
        onOpenChange={setIsOpen}
      >
        <p>No cached SQL Server execution plan was captured for this alert.</p>
        <div className="query-plan-empty">
          The session may have been idle with an open transaction, the cached plan may have aged out, or the collector identity may need DMV visibility such as VIEW SERVER STATE.
        </div>
      </CollapsibleSection>
    );
  }

  return (
    <CollapsibleSection
      title="Query Plan"
      summary={`${planEntries.length} plan${planEntries.length === 1 ? '' : 's'}`}
      className="query-plan-section"
      isOpen={isOpen}
      onOpenChange={setIsOpen}
    >
      <div className="query-plan-header">
        <p>Cached SQL Server execution plan captured during collection.</p>

        {planEntries.length > 1 ? (
          <label className="query-plan-select">
            <span>Plan</span>
            <select
              value={selectedPlanIndex}
              onChange={(event) => setSelectedPlanIndex(Number(event.target.value))}
            >
              {planEntries.map((plan, index) => (
                <option key={`${plan.label}-${index}`} value={index}>
                  {plan.label}
                </option>
              ))}
            </select>
          </label>
        ) : null}
      </div>

      <div className="query-plan-viewer" ref={containerRef} />
    </CollapsibleSection>
  );
}

function CollapsibleSection({ title, summary, className = '', defaultOpen = false, isOpen: controlledOpen, onOpenChange, children }) {
  const contentId = useId();
  const [internalOpen, setInternalOpen] = useState(defaultOpen);
  const isOpen = controlledOpen ?? internalOpen;

  function handleToggle() {
    const nextOpen = !isOpen;
    if (controlledOpen === undefined) {
      setInternalOpen(nextOpen);
    }
    onOpenChange?.(nextOpen);
  }

  return (
    <section className={`modal-section collapsible-section ${className}`.trim()}>
      <button
        type="button"
        className="collapsible-header"
        aria-expanded={isOpen}
        aria-controls={contentId}
        onClick={handleToggle}
      >
        <span className="collapsible-title">
          {isOpen ? <ChevronDown aria-hidden="true" size={16} /> : <ChevronRight aria-hidden="true" size={16} />}
          <span>{title}</span>
        </span>
        {summary ? <span className="collapsible-summary">{summary}</span> : null}
      </button>
      {isOpen ? (
        <div id={contentId} className="collapsible-content">
          {children}
        </div>
      ) : null}
    </section>
  );
}

function DetailItem({ label, value, wide = false }) {
  return (
    <div className={wide ? 'detail-item detail-item-wide' : 'detail-item'}>
      <span>{label}</span>
      <strong>{formatDetailValue(value)}</strong>
    </div>
  );
}

function StructuredDetails({ value }) {
  if (Array.isArray(value)) {
    return (
      <div className="nested-detail-list">
        {value.map((item, index) => (
          <div className="nested-detail" key={index}>
            <StructuredDetails value={item} />
          </div>
        ))}
      </div>
    );
  }

  if (value && typeof value === 'object') {
    return (
      <div className="detail-key-values">
        {Object.entries(value).map(([key, itemValue]) => (
          <div className="detail-row" key={key}>
            <span>{formatDetailLabel(key)}</span>
            <div>{renderDetailValue(itemValue)}</div>
          </div>
        ))}
      </div>
    );
  }

  return <span>{formatDetailValue(value)}</span>;
}

function renderDetailValue(value) {
  if (Array.isArray(value) || (value && typeof value === 'object')) {
    return <StructuredDetails value={value} />;
  }

  return <span>{formatDetailValue(value)}</span>;
}

function loadQueryPlanRenderer() {
  if (typeof window === 'undefined') {
    return Promise.reject(new Error('Query plan rendering requires a browser.'));
  }

  if (window.QP?.showPlan) {
    return Promise.resolve(window.QP);
  }

  if (!queryPlanRendererPromise) {
    queryPlanRendererPromise = new Promise((resolve, reject) => {
      try {
        const patchedScript = queryPlanScript
          .replace('})(this, function(window, document) {', '})(window, function(window, document) {')
          .replace('var SVG = this.SVG = function(element) {', 'var SVG = window.SVG = function(element) {');

        const load = new Function(
          'window',
          'document',
          `
            var define = undefined;
            var exports = undefined;
            var module = undefined;
            ${patchedScript}
            return window.QP;
          `
        );

        const renderer = load(window, document);
        if (!renderer?.showPlan) {
          reject(new Error('Query plan renderer did not initialize.'));
          return;
        }

        resolve(renderer);
      } catch (err) {
        reject(err);
      }
    });
  }

  return queryPlanRendererPromise;
}

function isPlanAwareAlertType(...values) {
  return values.some((value) => {
    const normalizedValue = String(value ?? '').trim().toLowerCase();
    return (
      normalizedValue === 'blockingchain' ||
      normalizedValue === 'longrunningtransaction' ||
      normalizedValue === 'activetransactionlogreusewait' ||
      normalizedValue.includes('collect-blockingsessions.ps1') ||
      normalizedValue.includes('collect-longrunningtransactions.ps1')
    );
  });
}

function hasBlockingEvidence(details) {
  return (
    normalizeEvidenceList(details?.leadBlockerHeldLocks).length > 0 ||
    normalizeEvidenceList(details?.blockedSessions).length > 0 ||
    normalizeEvidenceList(details?.blockingEvidence).length > 0
  );
}

function getBlockingContext(details) {
  if (!details || typeof details !== 'object') {
    return null;
  }

  const contextKeys = [
    'leadBlockerSessionId',
    'blockedSessionId',
    'blockingSessionId',
    'sessionId',
    'waitType',
    'waitDurationMs',
    'waitResource',
    'blockedObjectName',
    'blockedLockMode',
    'lockMode',
    'command',
    'databaseName',
    'loginName',
    'hostName',
    'programName',
    'sqlText',
    'leadBlockerSqlText',
    'blockedSqlText'
  ];

  const context = Object.fromEntries(
    contextKeys
      .filter((key) => hasRenderableDetail(details[key]))
      .map((key) => [key, details[key]])
  );

  const hasBlockingSignal = [
    'leadBlockerSessionId',
    'blockedSessionId',
    'blockingSessionId',
    'waitType',
    'waitResource',
    'blockedObjectName',
    'blockedLockMode',
    'lockMode'
  ].some((key) => hasRenderableDetail(details[key]));

  return hasBlockingSignal && Object.keys(context).length > 0 ? context : null;
}

function normalizeEvidenceList(value) {
  if (Array.isArray(value)) {
    return value;
  }

  if (value && typeof value === 'object') {
    return [value];
  }

  if (typeof value === 'string' && value.trim().length > 0) {
    try {
      const parsedValue = JSON.parse(value);
      if (Array.isArray(parsedValue)) {
        return parsedValue;
      }
      if (parsedValue && typeof parsedValue === 'object') {
        return [parsedValue];
      }
    } catch {
      return [{ value }];
    }
  }

  return [];
}

function collectQueryPlans(value, path = [], plans = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectQueryPlans(item, [...path, `item ${index + 1}`], plans));
    return plans;
  }

  if (value && typeof value === 'object') {
    Object.entries(value).forEach(([key, itemValue]) => {
      if (isQueryPlanXmlField(key, itemValue)) {
        plans.push({
          label: formatQueryPlanLabel([...path, key]),
          planXml: itemValue
        });
        return;
      }

      collectQueryPlans(itemValue, [...path, key], plans);
    });
  }

  return plans;
}

function stripQueryPlanXml(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => stripQueryPlanXml(item))
      .filter((item) => item !== undefined);
  }

  if (value && typeof value === 'object') {
    const cleanedEntries = Object.entries(value)
      .filter(([key, itemValue]) => !isQueryPlanXmlField(key, itemValue))
      .map(([key, itemValue]) => [key, stripQueryPlanXml(itemValue)])
      .filter(([, itemValue]) => itemValue !== undefined);

    return Object.fromEntries(cleanedEntries);
  }

  return value;
}

function stripDedicatedEvidence(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => stripDedicatedEvidence(item))
      .filter((item) => item !== undefined);
  }

  if (value && typeof value === 'object') {
    const cleanedEntries = Object.entries(value)
      .filter(([key]) => !isDedicatedEvidenceField(key))
      .map(([key, itemValue]) => [key, stripDedicatedEvidence(itemValue)])
      .filter(([, itemValue]) => itemValue !== undefined);

    return Object.fromEntries(cleanedEntries);
  }

  return value;
}

function isQueryPlanXmlField(key, value) {
  return (
    typeof value === 'string' &&
    value.trim().length > 0 &&
    (/(^|_)query_plan_xml$/i.test(key) || /queryPlanXml$/i.test(key) || value.trimStart().startsWith('<ShowPlanXML'))
  );
}

function isDedicatedEvidenceField(key) {
  return ['leadBlockerHeldLocks', 'blockedSessions', 'blockingEvidence'].includes(key);
}

function hasRenderableDetail(value) {
  if (Array.isArray(value)) {
    return value.length > 0;
  }

  if (value && typeof value === 'object') {
    return Object.keys(value).length > 0;
  }

  return value !== null && value !== undefined && value !== '';
}

function formatQueryPlanLabel(path) {
  const label = path
    .map((part) => {
      if (String(part).startsWith('item ')) {
        return `#${String(part).replace('item ', '')}`;
      }

      return formatDetailLabel(part);
    })
    .join(' / ');

  return label
    .replace(/\s*Query Plan Xml$/i, ' Query plan')
    .replace(/\s*Plan Xml$/i, ' plan')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseAlertDetails(detailsJson) {
  if (!detailsJson) {
    return null;
  }

  try {
    return JSON.parse(detailsJson);
  } catch {
    return {
      rawDetails: detailsJson
    };
  }
}

function formatDetailLabel(value) {
  return String(value)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatDetailValue(value) {
  if (value === null || value === undefined || value === '') {
    return '-';
  }

  if (Array.isArray(value)) {
    return value.join(', ');
  }

  return String(value);
}
