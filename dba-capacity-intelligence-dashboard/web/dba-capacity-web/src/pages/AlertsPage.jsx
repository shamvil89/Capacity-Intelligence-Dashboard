import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronRight, Copy, Download, Info, Mail, Maximize2, Trash2, X } from 'lucide-react';
import queryPlanScript from 'html-query-plan/dist/qp.js?raw';
import 'html-query-plan/css/qp.css';
import ColumnFilter from '../components/ColumnFilter.jsx';
import DataState from '../components/DataState.jsx';
import RiskBadge from '../components/RiskBadge.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { useTimezone } from '../components/TimezoneContext.jsx';
import { formatDateTime, formatRemainingTimeFromDays, formatStorageFromGb } from '../components/formatters.js';
import { containsText, getSelectedFilterFields, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const alertFilterColumns = [
  { key: 'environment', label: 'Environment' },
  { key: 'serverName', label: 'Server' },
  { key: 'databaseName', label: 'Database' },
  { key: 'alertType', label: 'Type' },
  { key: 'severity', label: 'Severity' },
  { key: 'status', label: 'Status', field: (row) => (row.isResolved ? 'Resolved' : 'Active') },
  { key: 'message', label: 'Message' },
  { key: 'sourceScript', label: 'Source' },
  { key: 'detailsJson', label: 'Evidence' }
];
let queryPlanRendererPromise;

export default function AlertsPage({ mode = 'active' }) {
  const { effectiveTimeZone } = useTimezone();
  const [alerts, setAlerts] = useState([]);
  const [selectedAlert, setSelectedAlert] = useState(null);
  const [containsFilter, setContainsFilter] = useState('');
  const [filterColumns, setFilterColumns] = useState(alertFilterColumns.map((column) => column.key));
  const [sortState, setSortState] = useState({ key: 'alertTime', direction: 'desc' });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const isHistoryMode = mode === 'history';

  useEffect(() => {
    let isMounted = true;

    async function load() {
      setIsLoading(true);
      setError('');

      try {
        const rows = isHistoryMode ? await api.getAlertHistory(500) : await api.getActiveAlerts();
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
  }, [isHistoryMode]);

  const visibleAlerts = useMemo(() => {
    const activeFilterFields = getSelectedFilterFields(alertFilterColumns, filterColumns);
    const filteredRows = alerts.filter((item) => {
      const matchesContains = containsText(item, activeFilterFields, containsFilter);

      return matchesContains;
    });

    return sortRows(filteredRows, sortState, {
      alertTime: 'date',
      resolvedAt: 'date',
      severity: 'risk'
    });
  }, [alerts, containsFilter, filterColumns, sortState]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  async function handleDeleteAlert(alert) {
    if (!alert.alertId) {
      setError('This alert cannot be deleted because it does not have an alert id.');
      return;
    }

    const databaseText = alert.databaseName ? `/${alert.databaseName}` : '';
    const confirmed = window.confirm(
      `Delete ${alert.alertType} for ${alert.serverName}${databaseText}? If the issue is still active, the next collector run can raise it again.`
    );

    if (!confirmed) {
      return;
    }

    try {
      setError('');
      await api.deleteAlert(alert.alertId);
      setAlerts((currentRows) => currentRows.filter((row) => row.alertId !== alert.alertId));
      setSelectedAlert((currentAlert) => (currentAlert?.alertId === alert.alertId ? null : currentAlert));
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>{isHistoryMode ? 'Resolved Alert History' : 'Active Alerts'}</h2>
          <p className="subtle">
            {isHistoryMode
              ? 'Resolved repository alerts retired by later collector and forecast runs.'
              : 'Current unresolved repository alerts from the latest collector and forecast runs.'}
          </p>
        </div>
      </div>

      <DataState isLoading={isLoading} error={error} isEmpty={alerts.length === 0}>
        <div className="table-panel alerts-panel">
          <div className="table-panel-header">
            <h3>{isHistoryMode ? 'Resolved Alerts' : 'Alert Queue'}</h3>
            <span>{visibleAlerts.length} rows</span>
          </div>

          <div className="table-controls alerts-controls">
            <ColumnFilter
              columns={alertFilterColumns}
              selectedColumns={filterColumns}
              value={containsFilter}
              onChange={setContainsFilter}
              onSelectedColumnsChange={setFilterColumns}
              placeholder="Environment, server, database, type, severity, message, evidence"
            />
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleAlerts.length === 0}>
            <div className="table-scroll">
              <table className={isHistoryMode ? 'alerts-table alerts-history-table' : 'alerts-table'}>
                <thead>
                  <tr>
                    <th><SortableHeader label="Time" sortKey="alertTime" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Environment" sortKey="environment" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Alert Type" sortKey="alertType" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Severity" sortKey="severity" sortState={sortState} onSort={handleSort} /></th>
                    {isHistoryMode ? <th><SortableHeader label="Status" sortKey="isResolved" sortState={sortState} onSort={handleSort} /></th> : null}
                    {isHistoryMode ? <th><SortableHeader label="Resolved" sortKey="resolvedAt" sortState={sortState} onSort={handleSort} /></th> : null}
                    <th><SortableHeader label="Message" sortKey="message" sortState={sortState} onSort={handleSort} /></th>
                    <th>Actions</th>
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
                      {isHistoryMode ? <td><AlertStatusBadge isResolved={item.isResolved} /></td> : null}
                      {isHistoryMode ? <td>{item.resolvedAt ? formatDateTime(item.resolvedAt, effectiveTimeZone) : '-'}</td> : null}
                      <td className="recommendation-cell alert-message-cell">{item.message}</td>
                      <td>
                        <div className="row-actions">
                          <button type="button" className="secondary-action" onClick={() => setSelectedAlert(item)}>
                            <Info aria-hidden="true" size={14} />
                            More info
                          </button>
                          <button
                            type="button"
                            className="secondary-action danger-action"
                            onClick={() => handleDeleteAlert(item)}
                            disabled={!item.alertId}
                          >
                            <Trash2 aria-hidden="true" size={14} />
                            Delete
                          </button>
                        </div>
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
  const nowMs = useNowMs(hasLiveDurationDetails(details));
  const displayDetails = useMemo(() => enrichLiveDurationDetails(details, nowMs), [details, nowMs]);
  const displayMessage = useMemo(() => formatAlertMessage(alert, displayDetails), [alert, displayDetails]);
  const resolutionSteps = useMemo(() => getResolutionSteps(alert, displayDetails), [alert, displayDetails]);
  const emailAttachments = useMemo(() => collectEmailAttachments(alert, displayDetails), [alert, displayDetails]);
  const emailSubject = useMemo(() => buildAlertEmailSubject(alert), [alert]);
  const emailBody = useMemo(
    () => buildAlertEmailBody(alert, displayDetails, displayMessage, resolutionSteps, emailAttachments, effectiveTimeZone),
    [alert, displayDetails, displayMessage, resolutionSteps, emailAttachments, effectiveTimeZone]
  );
  const hasDedicatedEvidence = useMemo(() => hasBlockingEvidence(displayDetails), [displayDetails]);
  const evidenceDetails = useMemo(() => {
    const cleanedDetails = stripQueryPlanXml(displayDetails);
    return hasDedicatedEvidence ? stripDedicatedEvidence(cleanedDetails) : cleanedDetails;
  }, [displayDetails, hasDedicatedEvidence]);

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
            <DetailItem label="Status" value={alert.isResolved ? 'Resolved' : 'Active'} />
            {alert.resolvedAt ? <DetailItem label="Resolved" value={formatDateTime(alert.resolvedAt, effectiveTimeZone)} /> : null}
            <DetailItem label="Source" value={alert.sourceScript || displayDetails?.sourceScripts || '-'} wide />
          </div>

          <section className="modal-section">
            <h4>Message</h4>
            <p>{displayMessage}</p>
          </section>

          <BlockingEvidenceSection details={displayDetails} />

          <QueryPlanSection alertType={alert.alertType} sourceScript={alert.sourceScript} details={displayDetails} />

          <section className="modal-section">
            <h4>Evidence</h4>
            {hasRenderableDetail(evidenceDetails) ? (
              <StructuredDetails value={evidenceDetails} />
            ) : (
              <p>No additional structured details were stored for this alert.</p>
            )}
          </section>

          <ResolutionStepsSection steps={resolutionSteps} />

          <EmailBodySection body={emailBody} subject={emailSubject} attachments={emailAttachments} />
        </div>
      </section>
    </div>
  );
}

function AlertStatusBadge({ isResolved }) {
  return (
    <span className={isResolved ? 'alert-status-badge resolved' : 'alert-status-badge active'}>
      {isResolved ? 'Resolved' : 'Active'}
    </span>
  );
}

function useNowMs(isEnabled) {
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    if (!isEnabled) {
      return undefined;
    }

    setNowMs(Date.now());
    const intervalId = window.setInterval(() => setNowMs(Date.now()), 30000);
    return () => window.clearInterval(intervalId);
  }, [isEnabled]);

  return nowMs;
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
                  <th>Resource Detail</th>
                  <th>Mode</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {heldLocks.map((lock, index) => (
                  <tr key={`${lock.databaseName}-${lock.objectName}-${lock.lockMode}-${index}`}>
                    <td>{formatDetailValue(lock.databaseName)}</td>
                    <td>{formatDetailValue(formatLockObject(lock))}</td>
                    <td>{formatDetailValue(lock.resourceType)}</td>
                    <td>{formatDetailValue(formatLockResourceDetail(lock))}</td>
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

function ResolutionStepsSection({ steps }) {
  if (!steps.length) {
    return null;
  }

  return (
    <CollapsibleSection title="Steps to Resolve" summary={`${steps.length} step${steps.length === 1 ? '' : 's'}`}>
      <ol className="resolution-steps">
        {steps.map((step, index) => (
          <li key={`${step}-${index}`}>{step}</li>
        ))}
      </ol>
    </CollapsibleSection>
  );
}

function EmailBodySection({ body, subject, attachments = [] }) {
  const [copyStatus, setCopyStatus] = useState('');
  const [outlookStatus, setOutlookStatus] = useState('');

  if (!body) {
    return null;
  }

  async function handleCopyBody() {
    try {
      await navigator.clipboard.writeText(`Subject: ${subject}\n\n${body}`);
      setCopyStatus('Copied');
      window.setTimeout(() => setCopyStatus(''), 2200);
    } catch {
      setCopyStatus('Copy failed');
      window.setTimeout(() => setCopyStatus(''), 2200);
    }
  }

  function handleOpenOutlookDraft() {
    const outlookBody = body;
    const draftUrl = buildMailDraftUrl(subject, outlookBody);

    if (draftUrl.length > 7500) {
      navigator.clipboard.writeText(`Subject: ${subject}\n\n${outlookBody}`).catch(() => {});
      window.location.href = buildMailDraftUrl(subject, 'The DBA Capacity alert email body was copied to your clipboard. Paste it into this draft before sending.');
      setOutlookStatus('Copied for Outlook');
      window.setTimeout(() => setOutlookStatus(''), 2600);
      return;
    }

    window.location.href = draftUrl;
  }

  function handleDownloadAllAttachments() {
    attachments.forEach((attachment, index) => {
      window.setTimeout(() => downloadTextAttachment(attachment), index * 100);
    });
  }

  return (
    <CollapsibleSection title="Email Body" summary={`${attachments.length} attachment${attachments.length === 1 ? '' : 's'}`}>
      <div className="email-actions">
        <button type="button" className="secondary-action" onClick={handleCopyBody}>
          <Copy aria-hidden="true" size={14} />
          {copyStatus || 'Copy text'}
        </button>
        <button type="button" className="secondary-action" onClick={handleOpenOutlookDraft}>
          <Mail aria-hidden="true" size={14} />
          {outlookStatus || 'Open Outlook app'}
        </button>
        {attachments.length > 0 ? (
          <button type="button" className="secondary-action" onClick={handleDownloadAllAttachments}>
            <Download aria-hidden="true" size={14} />
            Download all evidence
          </button>
        ) : null}
      </div>

      <div className="email-subject-preview">
        <span>Subject</span>
        <strong>{subject}</strong>
      </div>

      {attachments.length > 0 ? (
        <div className="email-attachments">
          <strong>Evidence attachments</strong>
          <div className="email-attachment-list">
            {attachments.map((attachment) => (
              <button
                type="button"
                className="email-attachment-item"
                key={attachment.fileName}
                onClick={() => downloadTextAttachment(attachment)}
              >
                <Download aria-hidden="true" size={14} />
                <span>{attachment.fileName}</span>
              </button>
            ))}
          </div>
          <p>Download these files and attach them before sending the Outlook draft.</p>
        </div>
      ) : null}

      <pre className="email-body-preview">{body}</pre>
    </CollapsibleSection>
  );
}

function buildMailDraftUrl(subject, body) {
  return `mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function QueryPlanSection({ alertType, sourceScript, details }) {
  const containerRef = useRef(null);
  const fullscreenContainerRef = useRef(null);
  const planEntries = useMemo(() => collectQueryPlans(details), [details]);
  const isPlanAwareAlert = isPlanAwareAlertType(alertType, details?.category, sourceScript, details?.sourceScripts);
  const [isOpen, setIsOpen] = useState(() => planEntries.length > 0);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [selectedPlanIndex, setSelectedPlanIndex] = useState(0);
  const selectedPlan = planEntries[Math.min(selectedPlanIndex, Math.max(planEntries.length - 1, 0))];

  useEffect(() => {
    setSelectedPlanIndex(0);
    setIsOpen(planEntries.length > 0);
    setIsFullscreen(false);
  }, [planEntries.length]);

  useEffect(() => {
    if (!isFullscreen) {
      return undefined;
    }

    function handleKeyDown(event) {
      if (event.key === 'Escape') {
        setIsFullscreen(false);
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isFullscreen]);

  useRenderedQueryPlan(containerRef, selectedPlan, isOpen && Boolean(selectedPlan));
  useRenderedQueryPlan(fullscreenContainerRef, selectedPlan, isFullscreen && Boolean(selectedPlan));

  function handlePlanChange(event) {
    setSelectedPlanIndex(Number(event.target.value));
  }

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

  function renderPlanSelector() {
    return planEntries.length > 1 ? (
      <label className="query-plan-select">
        <span>Plan</span>
        <select value={selectedPlanIndex} onChange={handlePlanChange}>
          {planEntries.map((plan, index) => (
            <option key={`${plan.label}-${index}`} value={index}>
              {plan.label}
            </option>
          ))}
        </select>
      </label>
    ) : null;
  }

  return (
    <>
      <CollapsibleSection
        title="Query Plan"
        summary={`${planEntries.length} plan${planEntries.length === 1 ? '' : 's'}`}
        className="query-plan-section"
        isOpen={isOpen}
        onOpenChange={setIsOpen}
      >
        <div className="query-plan-header">
          <p>Cached SQL Server execution plan captured during collection.</p>

          <div className="query-plan-header-actions">
            {renderPlanSelector()}
            <button type="button" className="secondary-action" onClick={() => setIsFullscreen(true)}>
              <Maximize2 aria-hidden="true" size={14} />
              Fullscreen
            </button>
          </div>
        </div>

        <div className="query-plan-viewer" ref={containerRef} />
      </CollapsibleSection>

      {isFullscreen ? (
        <div className="query-plan-fullscreen-backdrop" role="presentation" onMouseDown={() => setIsFullscreen(false)}>
          <section
            className="query-plan-fullscreen-panel"
            role="dialog"
            aria-modal="true"
            aria-labelledby="query-plan-fullscreen-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <header className="query-plan-fullscreen-header">
              <div>
                <p className="eyebrow">Query plan</p>
                <h3 id="query-plan-fullscreen-title">{selectedPlan?.label || 'Execution plan'}</h3>
              </div>
              <div className="query-plan-fullscreen-actions">
                {renderPlanSelector()}
                <button type="button" className="icon-action" aria-label="Close fullscreen query plan" onClick={() => setIsFullscreen(false)}>
                  <X aria-hidden="true" size={18} />
                </button>
              </div>
            </header>

            <div className="query-plan-viewer query-plan-viewer-fullscreen" ref={fullscreenContainerRef} />
          </section>
        </div>
      ) : null}
    </>
  );
}

function useRenderedQueryPlan(containerRef, selectedPlan, shouldRender) {
  useEffect(() => {
    const container = containerRef.current;
    let isCancelled = false;

    if (!shouldRender || !container || !selectedPlan) {
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
  }, [containerRef, selectedPlan, shouldRender]);
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

function collectEmailAttachments(alert, details) {
  const baseName = buildAttachmentBaseName(alert);
  const sqlTextEntries = uniqueContentEntries(collectSqlTextEntries(details), 'sqlText');
  const queryPlanEntries = uniqueContentEntries(collectQueryPlans(details), 'planXml');

  return [
    ...sqlTextEntries.map((entry, index) => ({
      fileName: `${baseName}_${String(index + 1).padStart(2, '0')}_${sanitizeFileName(entry.label || 'query')}.sql`,
      mimeType: 'application/sql',
      description: `${entry.label} query text`,
      content: buildSqlAttachmentContent(alert, entry)
    })),
    ...queryPlanEntries.map((entry, index) => ({
      fileName: `${baseName}_${String(index + 1).padStart(2, '0')}_${sanitizeFileName(entry.label || 'query-plan')}.sqlplan`,
      mimeType: 'application/sqlplan+xml',
      description: `${entry.label} execution plan`,
      content: entry.planXml.trim()
    }))
  ];
}

function collectSqlTextEntries(value, path = [], entries = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectSqlTextEntries(item, [...path, `item ${index + 1}`], entries));
    return entries;
  }

  if (value && typeof value === 'object') {
    Object.entries(value).forEach(([key, itemValue]) => {
      if (isSqlTextField(key, itemValue)) {
        entries.push({
          label: formatSqlTextLabel([...path, key]),
          sqlText: itemValue
        });
        return;
      }

      collectSqlTextEntries(itemValue, [...path, key], entries);
    });
  }

  return entries;
}

function isSqlTextField(key, value) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return false;
  }

  return (
    !value.trimStart().startsWith('<ShowPlanXML') &&
    (/(^|_)sql_text$/i.test(key) || /sqlText$/i.test(key) || /queryText$/i.test(key) || /statementText$/i.test(key))
  );
}

function uniqueContentEntries(entries, contentKey) {
  const seen = new Set();

  return entries.filter((entry) => {
    const content = String(entry?.[contentKey] ?? '').trim();
    if (!content) {
      return false;
    }

    const key = `${entry.label ?? ''}|${content}`;
    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

function buildAttachmentBaseName(alert) {
  return sanitizeFileName(
    [
      'dba-alert',
      alert.alertId ?? alert.alertTime ?? '',
      alert.alertType ?? 'alert',
      alert.serverName ?? 'server',
      alert.databaseName ?? 'database'
    ]
      .filter(Boolean)
      .join('_')
  );
}

function sanitizeFileName(value) {
  const sanitized = String(value)
    .replace(/[^a-z0-9._-]+/gi, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 120);

  return sanitized || 'evidence';
}

function buildSqlAttachmentContent(alert, entry) {
  return [
    '-- DBA Capacity alert evidence',
    `-- Alert id: ${formatDetailValue(alert.alertId)}`,
    `-- Alert type: ${formatDetailValue(alert.alertType)}`,
    `-- Severity: ${formatDetailValue(alert.severity)}`,
    `-- Server: ${formatDetailValue(alert.serverName)}`,
    `-- Database: ${formatDetailValue(alert.databaseName)}`,
    `-- Captured field: ${formatDetailValue(entry.label)}`,
    '',
    entry.sqlText.trim(),
    ''
  ].join('\n');
}

function downloadTextAttachment(attachment) {
  const blob = new Blob([attachment.content], { type: `${attachment.mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');

  link.href = url;
  link.download = attachment.fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
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

function hasLiveDurationDetails(value) {
  if (Array.isArray(value)) {
    return value.some((item) => hasLiveDurationDetails(item));
  }

  if (value && typeof value === 'object') {
    if (value.transactionBeginTime && value.durationMinutes !== undefined) {
      return true;
    }

    return Object.values(value).some((item) => hasLiveDurationDetails(item));
  }

  return false;
}

function enrichLiveDurationDetails(value, nowMs) {
  if (Array.isArray(value)) {
    return value.map((item) => enrichLiveDurationDetails(item, nowMs));
  }

  if (!value || typeof value !== 'object') {
    return value;
  }

  const liveDurationMinutes = calculateLiveDurationMinutes(value.transactionBeginTime, value.durationMinutes, nowMs);
  const entries = Object.entries(value);

  if (liveDurationMinutes === null) {
    return Object.fromEntries(entries.map(([key, itemValue]) => [key, enrichLiveDurationDetails(itemValue, nowMs)]));
  }

  const enrichedEntries = [];
  entries.forEach(([key, itemValue]) => {
    if (key === 'durationMinutes') {
      enrichedEntries.push([key, liveDurationMinutes]);
      enrichedEntries.push(['collectedDurationMinutes', itemValue]);
      enrichedEntries.push(['durationStatus', 'Live estimate from transaction begin time while this alert remains unresolved.']);
      return;
    }

    if (key !== 'collectedDurationMinutes' && key !== 'durationStatus') {
      enrichedEntries.push([key, enrichLiveDurationDetails(itemValue, nowMs)]);
    }
  });

  return Object.fromEntries(enrichedEntries);
}

function calculateLiveDurationMinutes(transactionBeginTime, collectedDurationMinutes, nowMs) {
  const beginDate = parseSourceLocalDateTime(transactionBeginTime);
  if (!beginDate) {
    return null;
  }

  const elapsedMinutes = (nowMs - beginDate.getTime()) / 60000;
  if (!Number.isFinite(elapsedMinutes)) {
    return null;
  }

  const collectedMinutes = Number(collectedDurationMinutes);
  const safeElapsedMinutes = Number.isFinite(collectedMinutes)
    ? Math.max(elapsedMinutes, collectedMinutes)
    : elapsedMinutes;

  return Number(Math.max(0, safeElapsedMinutes).toFixed(2));
}

function parseSourceLocalDateTime(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }

  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }

  const localSqlDateTime = value
    .trim()
    .replace(' ', 'T')
    .replace(/(\.\d{3})\d+/, '$1');
  const parsedDate = new Date(localSqlDateTime);

  return Number.isNaN(parsedDate.getTime()) ? null : parsedDate;
}

function formatAlertMessage(alert, details) {
  if (alert.alertType !== 'LongRunningTransaction' || !details?.sessionId || details.durationMinutes === undefined) {
    return alert.message;
  }

  const databaseText = details.databaseName ? ` in ${details.databaseName}` : '';
  return `Session ${details.sessionId} has an open transaction for ${formatDurationMinutes(details.durationMinutes)} minutes${databaseText}. Login: ${details.loginName || 'unknown'}.`;
}

function getResolutionSteps(alert, details) {
  const alertType = String(alert.alertType ?? details?.category ?? '').toLowerCase();

  if (alertType.includes('collectionfailure')) {
    return buildCollectionFailureResolutionSteps(alert, details);
  }

  switch (alertType) {
    case 'capacityrisk':
      return buildCapacityRiskResolutionSteps(alert, details);
    case 'logfileexhaustionrisk':
      return buildLogFileExhaustionResolutionSteps(alert, details);
    case 'fullrecoverynologbackup':
      return buildFullRecoveryNoLogBackupResolutionSteps(alert, details);
    case 'longrunningtransaction':
      return buildLongRunningTransactionResolutionSteps(alert, details);
    case 'blockingchain':
      return buildBlockingChainResolutionSteps(alert, details);
    case 'activetransactionlogreusewait':
      return buildActiveTransactionLogReuseResolutionSteps(alert, details);
    case 'alwaysonhealthissue':
    case 'alwaysonlogreusewait':
      return buildAlwaysOnResolutionSteps(alert, details);
    case 'replicationagentissue':
    case 'replicationlogreusewait':
      return buildReplicationResolutionSteps(alert, details);
    case 'tempdbusage':
      return buildTempDbResolutionSteps(alert, details);
    case 'diskspacelow':
      return buildDiskSpaceResolutionSteps(alert, details);
    case 'backupgrowth':
      return buildBackupGrowthResolutionSteps(alert, details);
    default:
      return buildDefaultResolutionSteps(alert, details);
  }
}

function buildDefaultResolutionSteps(alert, details) {
  return compactSteps([
    `Confirm the alert is still active for ${describeAlertTarget(alert, details)} by checking the latest collector run and the source evidence.`,
    `Review the captured source path: ${formatDetailValue(details?.sourceScripts || alert.sourceScript)}.`,
    'Validate the affected owner, application, maintenance window, and business impact before making any disruptive change.',
    getEvidenceDownloadHint(details),
    'Resolve the root cause, rerun the collector or forecast pipeline, and confirm the alert moves out of the active queue.'
  ]);
}

function buildCollectionFailureResolutionSteps(alert, details) {
  const metricName = details?.metricName || String(alert.alertType ?? '').split(':')[1] || 'collector metric';

  return compactSteps([
    `The ${metricName} collector failed for ${describeAlertTarget(alert, details)}. Open the latest collector pipeline run and search for ${formatDetailValue(details?.sourceScripts || alert.sourceScript)}.`,
    details?.errorMessage ? `Start with the captured error text: ${truncateText(details.errorMessage, 320)}.` : 'Capture the exact collector error text from the pipeline log.',
    'Validate repository connectivity first, then source SQL connectivity, authentication mode, firewall rules, certificate trust, and database context for the affected server/database.',
    getCollectorMetricSpecificStep(metricName),
    'After fixing the cause, rerun the collector pipeline. The matching CollectionFailure alert should resolve automatically when the metric succeeds.'
  ]);
}

function buildCapacityRiskResolutionSteps(alert, details) {
  return compactSteps([
    `Capacity forecast evidence for ${describeAlertTarget(alert, details)}: current size ${formatGb(details?.currentSizeGb)}, 7-day growth ${formatGb(details?.growth7DaysGb)}, 30-day growth ${formatGb(details?.growth30DaysGb)}, average daily growth ${formatGb(details?.averageGrowthPerDayGb)}, available space ${formatGb(details?.availableSpaceGb)}, estimated time remaining ${formatDaysRemaining(details?.estimatedDaysRemaining)}.`,
    details?.recommendation ? `Use the generated recommendation as the starting hypothesis: ${details.recommendation}` : null,
    'Check whether the growth is expected from a release, data load, index maintenance, retention change, or new table growth. Compare the database detail chart and Top Tables view for the same server/database.',
    'If growth is expected, plan the storage action: add/move storage, increase file max size, adjust autogrowth, archive/purge data, or compress/rebuild indexes after validating workload impact.',
    'If growth is not expected, identify the top new or fast-growing objects, confirm owner and application change, and pause non-essential data loads until headroom is restored.',
    'Rerun collection and forecast generation after remediation; active risk should fall and estimated time remaining should increase.'
  ]);
}

function buildLogFileExhaustionResolutionSteps(alert, details) {
  const projectedTime = details?.projectedHoursToCap === null || details?.projectedHoursToCap === undefined
    ? 'unknown'
    : formatRemainingTimeFromDays(Number(details.projectedHoursToCap) / 24, 'unknown');

  return compactSteps([
    `Transaction log evidence for ${describeAlertTarget(alert, details)}: current log ${formatGb(details?.currentLogSizeGb)}, used ${formatGb(details?.usedLogGb)}, free ${formatGb(details?.freeLogGb)}, effective cap ${formatGb(details?.effectiveLogCapGb)}, remaining ${formatGb(details?.remainingToCapGb)}, ${formatPercent(details?.percentOfEffectiveCap)} of cap used, projected time to cap ${projectedTime}.`,
    `The effective cap is constrained by the lower of configured max size, SQL Server log file cap (${formatGb(details?.sqlServerLogFileCapGb)}), and observed disk headroom on ${formatDetailValue(details?.sampleVolumeMountPoint)} with ${formatGb(details?.observedVolumeAvailableGb)} available.`,
    `Log reuse wait is ${formatDetailValue(details?.logReuseWait)} and recovery model is ${formatDetailValue(details?.recoveryModel)}. ${getLogReuseWaitAction(details?.logReuseWait)}`,
    'If the issue is missing log backups, take an immediate log backup only after confirming the backup chain and destination capacity; then fix the recurring log backup job.',
    'If the issue is an open transaction, blocking, Always On, or replication, clear that dependency first. Taking log backups alone will not truncate reusable log until the wait condition clears.',
    'Avoid shrinking as the first response. Add disk or raise file max size only when growth is legitimate or emergency headroom is needed; shrink later only after the root cause is fixed and DBA approval is recorded.',
    'After remediation, rerun file-size collection and alert generation. Confirm log reuse wait changes, used log drops or stabilizes, and projected time to cap is no longer urgent.'
  ]);
}

function buildFullRecoveryNoLogBackupResolutionSteps(alert, details) {
  const hasObservedLogBackup = hasRenderableDetail(details?.lastLogBackupFinishDate);
  const logReuseWait = String(details?.logReuseWait ?? '').toUpperCase();

  return compactSteps([
    `Backup evidence for ${describeAlertTarget(alert, details)}: recovery model ${formatDetailValue(details?.recoveryModel)}, current log ${formatGb(details?.currentLogSizeGb)}, log reuse wait ${formatDetailValue(details?.logReuseWait)}, last observed log backup ${hasObservedLogBackup ? formatDateEvidence(details.lastLogBackupFinishDate) : 'none in collected backup history'}, hours since last log backup ${hasObservedLogBackup ? formatHours(details?.hoursSinceLastLogBackup) : 'not available'}.`,
    logReuseWait === 'NOTHING'
      ? 'Log reuse wait is NOTHING, so this is currently a recoverability/RPO gap rather than proof that the log is blocked from truncating right now.'
      : `Log reuse wait is ${formatDetailValue(details?.logReuseWait)}. ${getLogReuseWaitAction(details?.logReuseWait)}`,
    'Confirm with the application/recovery owner whether FULL recovery is required for point-in-time restore, Always On, replication, or compliance.',
    hasObservedLogBackup
      ? 'If FULL recovery is required, take an immediate log backup to approved storage and investigate why the regular log backup interval was missed.'
      : 'If FULL recovery is required and no valid backup chain exists, take a full backup first to establish the chain, then start recurring log backups.',
    'Fix the SQL Agent or enterprise backup job schedule, credentials, storage path, compression/encryption settings, and monitoring so log backups run at the required RPO interval.',
    'If point-in-time recovery is not required, document approval and switch to SIMPLE recovery during an agreed change window.',
    'Rerun backup-size/file-size collection and alert generation. Confirm a recent log backup appears in collected history, or confirm the database was intentionally moved out of FULL recovery.'
  ]);
}

function buildLongRunningTransactionResolutionSteps(alert, details) {
  return compactSteps([
    `Open transaction evidence for ${describeAlertTarget(alert, details)}: session ${formatDetailValue(details?.sessionId)}, transaction ${formatDetailValue(details?.transactionId)}, began ${formatDateEvidence(details?.transactionBeginTime)}, live duration ${formatDurationMinutes(details?.durationMinutes)} minutes, login ${formatDetailValue(details?.loginName)}, host ${formatDetailValue(details?.hostName)}, program ${formatDetailValue(details?.programName)}, command ${formatDetailValue(details?.command)}, wait ${formatDetailValue(details?.waitType)}, blocked by ${formatDetailValue(details?.blockingSessionId)}.`,
    getEvidenceDownloadHint(details),
    hasRenderableDetail(details?.blockingSessionId) ? `Resolve blocker session ${details.blockingSessionId} first. The open transaction may not be able to finish until that blocker clears.` : 'Check whether the session is actively running, waiting, idle in transaction, or blocked before deciding on an action.',
    'Contact the login/application owner and ask whether the transaction can safely commit or roll back. Include the captured SQL text and plan when escalating.',
    'If the session is abandoned or causing log exhaustion/blocking, prepare rollback impact: estimate transaction work, notify stakeholders, and kill the session only with approval.',
    'After it clears, check log reuse wait and blocking again, then rerun the collector. The alert should retire when the session no longer appears in long-running transaction history.'
  ]);
}

function buildBlockingChainResolutionSteps(alert, details) {
  const heldLocks = normalizeEvidenceList(details?.leadBlockerHeldLocks);
  const blockedSessions = normalizeEvidenceList(details?.blockedSessions);
  const worstBlocked = getWorstBlockedSession(blockedSessions);
  const firstLock = heldLocks[0];

  return compactSteps([
    `Blocking evidence for ${describeAlertTarget(alert, details)}: lead blocker session ${formatDetailValue(details?.leadBlockerSessionId)}, login ${formatDetailValue(details?.leadBlockerLoginName)}, host ${formatDetailValue(details?.leadBlockerHostName)}, program ${formatDetailValue(details?.leadBlockerProgramName)}, status ${formatDetailValue(details?.leadBlockerStatus)}, command ${formatDetailValue(details?.leadBlockerCommand)}, running since ${formatDateEvidence(details?.leadBlockerRunningSince)}, duration ${formatDurationMinutes(details?.leadBlockerDurationMinutes)} minutes, blocked sessions ${formatDetailValue(details?.blockedSessionCount)}, max wait ${formatMs(details?.maxBlockedWaitMs)}.`,
    firstLock ? `Lead blocker is holding ${heldLocks.length} captured lock(s). Start with ${formatDetailValue(firstLock.databaseName)} / ${formatLockObject(firstLock)} / ${formatDetailValue(firstLock.resourceType)} / ${formatLockResourceDetail(firstLock)} in ${formatDetailValue(firstLock.lockMode)} mode.` : 'No held-lock rows were captured; use the lead blocker session, SQL text, and blocked session waits to investigate.',
    worstBlocked ? `Worst blocked session is ${formatDetailValue(worstBlocked.blockedSessionId)} waiting ${formatMs(worstBlocked.waitDurationMs)} on ${formatDetailValue(worstBlocked.waitType)} at ${formatDetailValue(worstBlocked.blockedObjectName || worstBlocked.waitResource)}. Review its SQL text before taking action on the blocker.` : null,
    getEvidenceDownloadHint(details),
    'Contact the owner of the lead blocker and ask them to commit, roll back, or stop the blocking workload. If the owner is unavailable, assess rollback cost and kill only under an approved incident/change path.',
    'For recurrence prevention, tune the lead blocker query/indexes, reduce transaction scope, batch large writes, review isolation level, and make sure user interactions are not holding open transactions.',
    'Rerun the blocking collector. Confirm blocked session count is zero or materially lower and no new BlockingChain alert is active.'
  ]);
}

function buildActiveTransactionLogReuseResolutionSteps(alert, details) {
  const longTransactions = normalizeEvidenceList(details?.longRunningTransactions);
  const blockingEvidence = normalizeEvidenceList(details?.blockingEvidence);
  const longestTransaction = getLongestTransaction(longTransactions);
  const worstBlocker = getWorstBlockedSession(blockingEvidence);

  return compactSteps([
    `Log truncation is waiting on ${formatDetailValue(details?.logReuseWait)} for ${describeAlertTarget(alert, details)}. Current log size is ${formatGb(details?.currentLogSizeGb)} and recovery model is ${formatDetailValue(details?.recoveryModel)}.`,
    longestTransaction ? `Longest captured transaction is session ${formatDetailValue(longestTransaction.sessionId)} for ${formatDurationMinutes(longestTransaction.durationMinutes)} minutes, login ${formatDetailValue(longestTransaction.loginName)}, host ${formatDetailValue(longestTransaction.hostName)}, program ${formatDetailValue(longestTransaction.programName)}, began ${formatDateEvidence(longestTransaction.transactionBeginTime)}.` : 'No long-running transaction row was captured in the recent evidence window; rerun collection or query active transactions directly on the source server.',
    worstBlocker ? `Recent blocking evidence points to lead blocker ${formatDetailValue(worstBlocker.leadBlockerSessionId)} blocking session ${formatDetailValue(worstBlocker.blockedSessionId)} for ${formatMs(worstBlocker.waitDurationMs)} on ${formatDetailValue(worstBlocker.waitType)}.` : null,
    getEvidenceDownloadHint(details),
    'Clear the open transaction or blocker first. Until it clears, the log cannot truncate even if log backups run successfully.',
    'After the transaction clears, take a log backup if the database is in FULL recovery and validate that log reuse wait changes away from ACTIVE_TRANSACTION.',
    'Rerun file-size, long-running transaction, blocking, and alert generation. Confirm used log space is stable/decreasing and no new active transaction wait alert remains.'
  ]);
}

function buildAlwaysOnResolutionSteps(alert, details) {
  const issueRows = [
    ...normalizeEvidenceList(details?.databaseIssues),
    ...normalizeEvidenceList(details?.alwaysOnEvidence)
  ];
  const worstIssue = issueRows.find((item) => item.isSuspended || item.connectedState === 'DISCONNECTED' || item.databaseSynchronizationHealth === 'NOT_HEALTHY' || item.replicaSynchronizationHealth === 'NOT_HEALTHY') || issueRows[0];

  return compactSteps([
    `Always On evidence for ${describeAlertTarget(alert, details)}: AG ${formatDetailValue(details?.availabilityGroupName || worstIssue?.availabilityGroupName)}, replica ${formatDetailValue(details?.replicaServerName || worstIssue?.replicaServerName)}, role ${formatDetailValue(details?.role || worstIssue?.role)}, connected state ${formatDetailValue(details?.connectedState || worstIssue?.connectedState)}, replica health ${formatDetailValue(details?.replicaSynchronizationHealth || worstIssue?.replicaSynchronizationHealth)}, database issue count ${formatDetailValue(details?.databaseIssueCount || issueRows.length)}.`,
    details?.hasConnectivityIssue || worstIssue?.lastConnectErrorDescription ? `Connectivity evidence: last error ${formatDetailValue(details?.lastConnectErrorNumber || worstIssue?.lastConnectErrorNumber)} - ${formatDetailValue(details?.lastConnectErrorDescription || worstIssue?.lastConnectErrorDescription)} at ${formatDateEvidence(details?.lastConnectErrorTimestamp || worstIssue?.lastConnectErrorTimestamp)}. Check endpoint state, SQL service account, DNS, firewall, cluster network, listener routing, and SQL error logs on both replicas.` : null,
    worstIssue ? `Database-level evidence: ${formatDetailValue(worstIssue.databaseName || details?.databaseName)} state ${formatDetailValue(worstIssue.synchronizationState || worstIssue.databaseSynchronizationState)}, health ${formatDetailValue(worstIssue.synchronizationHealth || worstIssue.databaseSynchronizationHealth)}, suspended ${formatDetailValue(worstIssue.isSuspended)}, suspend reason ${formatDetailValue(worstIssue.suspendReason)}, send queue ${formatKb(worstIssue.logSendQueueSizeKb)}, redo queue ${formatKb(worstIssue.redoQueueSizeKb)}.` : 'Open the Always On dashboard and identify the unhealthy replica/database row.',
    'If data movement is suspended, find the suspend reason before issuing RESUME. Resume only after the underlying storage/network/redo/log issue is understood.',
    'If queues are growing, determine whether the primary cannot send, the secondary cannot harden/redo, or the network is saturated. Check latency, disk, redo workers, and recent failover/maintenance events.',
    'Once connected and synchronized, rerun Always On health and alert generation. For AVAILABILITY_REPLICA log reuse waits, confirm the log reuse wait clears after the replica catches up.'
  ]);
}

function buildReplicationResolutionSteps(alert, details) {
  const replicationRows = normalizeEvidenceList(details?.replicationEvidence);
  const replicationIssue = replicationRows.find((item) => item.errorCode || item.errorText || /fail|retry/i.test(String(item.runStatusDescription ?? ''))) || replicationRows[0] || details;

  return compactSteps([
    `Replication evidence for ${describeAlertTarget(alert, details)}: publication ${formatDetailValue(details?.publication || replicationIssue?.publication)}, agent ${formatDetailValue(details?.agentName || replicationIssue?.agentName)}, type ${formatDetailValue(details?.agentType || replicationIssue?.agentType)}, status ${formatDetailValue(details?.runStatusDescription || replicationIssue?.runStatusDescription)}, subscriber ${formatDetailValue(details?.subscriberName || replicationIssue?.subscriberName)}, subscriber DB ${formatDetailValue(details?.subscriberDatabaseName || replicationIssue?.subscriberDatabaseName)}, latency ${formatSeconds(details?.latencySeconds || replicationIssue?.latencySeconds)}.`,
    (details?.errorText || replicationIssue?.errorText || details?.comments || replicationIssue?.comments) ? `Start with the replication error/comment: ${truncateText(details?.errorText || replicationIssue?.errorText || details?.comments || replicationIssue?.comments, 360)}.` : 'Open Replication Monitor and SQL Agent job history for the affected Log Reader, Distribution, Merge, or Snapshot agent.',
    'Validate distributor, publisher, and subscriber connectivity; agent login permissions; linked/distribution database availability; and whether the subscriber is offline or blocked.',
    details?.logReuseWait || alert.alertType === 'ReplicationLogReuseWait' ? `Because log reuse wait is ${formatDetailValue(details?.logReuseWait || 'REPLICATION')}, prioritize the Log Reader/Distribution path and distribution backlog so replicated transactions can clear from the publisher log.` : null,
    'Restart the failed/retrying agent only after the root error is understood. Reinitialize subscriptions only after confirming data impact and stakeholder approval.',
    'Rerun replication health and alert generation. Confirm agent status is healthy, latency is decreasing, and log reuse wait is no longer REPLICATION when applicable.'
  ]);
}

function buildTempDbResolutionSteps(alert, details) {
  const consumers = normalizeEvidenceList(details?.topConsumers);
  const topConsumer = consumers[0];

  return compactSteps([
    `TempDB evidence for ${describeAlertTarget(alert, details)}: total ${formatMb(details?.tempdbSizeMb)}, used ${formatMb(details?.usedSpaceMb)} (${formatPercent(details?.usedPercent)}), free ${formatMb(details?.freeSpaceMb)}, user objects ${formatMb(details?.userObjectsMb)}, internal objects ${formatMb(details?.internalObjectsMb)}, version store ${formatMb(details?.versionStoreMb)}.`,
    topConsumer ? `Top captured consumer is session ${formatDetailValue(topConsumer.sessionId)} request ${formatDetailValue(topConsumer.requestId)}, database ${formatDetailValue(topConsumer.databaseName)}, login ${formatDetailValue(topConsumer.loginName)}, host ${formatDetailValue(topConsumer.hostName)}, program ${formatDetailValue(topConsumer.programName)}, command ${formatDetailValue(topConsumer.command)}, wait ${formatDetailValue(topConsumer.waitType)}, allocated ${formatMb(topConsumer.totalAllocatedMb)}.` : 'No session-level TempDB consumers were captured; rerun collection or inspect current TempDB session usage directly.',
    getEvidenceDownloadHint(details),
    'If user objects dominate, look for temp table/table variable growth, large sorts/hash spills, ETL batches, or reporting queries. Tune the query, add supporting indexes, or break the workload into smaller batches.',
    'If internal objects dominate, inspect execution plans for spills and memory grants. Tune joins/sorts, update stats, and review concurrent memory pressure.',
    'If version store is high, investigate long-running snapshot/RCSI transactions and readers preventing cleanup.',
    'If immediate headroom is needed, add TempDB space/files on suitable storage. Do not restart SQL Server unless it is an approved last resort.',
    'Rerun TempDB collection and confirm used percent and top consumer allocation drop.'
  ]);
}

function buildDiskSpaceResolutionSteps(alert, details) {
  return compactSteps([
    `Disk evidence for ${describeAlertTarget(alert, details)}: volume ${formatDetailValue(details?.volumeMountPoint)}, logical volume ${formatDetailValue(details?.logicalVolumeName)}, total ${formatGb(details?.totalGb)}, used ${formatGb(details?.usedGb)} (${formatPercent(details?.usedPercent)}), available ${formatGb(details?.availableGb)}.`,
    'Identify what is on the affected volume: data files, log files, backups, SQL error logs, dump files, trace/XEvent files, installer media, or unrelated application files.',
    'Free space only through approved cleanup paths first: old backups beyond retention, stale dumps, old logs, or moving non-SQL files. Preserve anything required for restore or audit.',
    'If database/log growth is legitimate, add disk, move files to a larger volume, or adjust file max size/autogrowth through a change-controlled action.',
    'Review nearby log/database capacity alerts for the same server/volume so disk remediation also addresses the file that is likely to grow next.',
    'Rerun disk and file-size collection. Confirm available GB and used percent are back above your operational threshold.'
  ]);
}

function buildBackupGrowthResolutionSteps(alert, details) {
  return compactSteps([
    `Backup growth evidence for ${describeAlertTarget(alert, details)}: backup type ${formatDetailValue(details?.backupType)}, finish time ${formatDateEvidence(details?.backupFinishDate)}, latest size ${formatGb(details?.backupSizeGb)}, 30-day average ${formatGb(details?.averageBackupSizeGb)}.`,
    'Check whether compression, encryption, backup type, copy-only behavior, or backup tool settings changed.',
    'Correlate with large data loads, index maintenance, bulk operations, retention changes, partition switches, or unusual transaction volume around the backup finish time.',
    'Validate backup target capacity, retention policy, and restore requirements. Larger backups may be expected but still require storage planning.',
    'If the growth is not expected, identify the database objects or workload that drove the size increase and engage the application owner.',
    'Rerun backup collection after the next scheduled backup and update capacity planning if the new size is legitimate.'
  ]);
}

function compactSteps(steps) {
  return steps
    .filter((step) => typeof step === 'string' && step.trim().length > 0)
    .map((step) => step.replace(/\s+/g, ' ').trim());
}

function describeAlertTarget(alert, details) {
  const serverName = details?.serverName || alert.serverName || 'the affected server';
  const databaseName = details?.databaseName || alert.databaseName;

  return databaseName ? `${serverName}/${databaseName}` : serverName;
}

function getEvidenceDownloadHint(details) {
  const sqlCount = collectSqlTextEntries(details).length;
  const planCount = collectQueryPlans(details).length;
  const evidence = [];

  if (sqlCount > 0) {
    evidence.push(`${sqlCount} captured SQL text item${sqlCount === 1 ? '' : 's'}`);
  }

  if (planCount > 0) {
    evidence.push(`${planCount} cached execution plan${planCount === 1 ? '' : 's'}`);
  }

  return evidence.length > 0
    ? `Use the Query Plan and Email Body sections in More info to review/download ${evidence.join(' and ')} before contacting the application owner.`
    : null;
}

function getCollectorMetricSpecificStep(metricName) {
  const normalizedMetric = String(metricName ?? '').toLowerCase();

  if (normalizedMetric.includes('database')) {
    return 'For DatabaseSize failures, verify the login can enumerate online databases and read database size metadata in each target database.';
  }

  if (normalizedMetric.includes('file')) {
    return 'For FileSize failures, verify database metadata visibility, file metadata access, and permissions to read log reuse wait and file space information.';
  }

  if (normalizedMetric.includes('disk')) {
    return 'For DiskSpace failures, verify instance-level DMV permissions and volume metadata access; Azure SQL Database rows should be server_type AzureSQL so disk collection is skipped.';
  }

  if (normalizedMetric.includes('table')) {
    return 'For TableSize failures, verify the login can connect to the user database and read object, partition, and allocation metadata.';
  }

  if (normalizedMetric.includes('backup')) {
    return 'For BackupSize failures, verify access to msdb backup history and any enterprise backup metadata used by the collector.';
  }

  if (normalizedMetric.includes('temp')) {
    return 'For TempDB failures, verify permissions to read TempDB/session DMVs and confirm the source is not Azure SQL Database, where the instance-level collector is skipped.';
  }

  if (normalizedMetric.includes('blocking') || normalizedMetric.includes('longrunning')) {
    return 'For blocking or long-transaction failures, verify VIEW SERVER STATE or equivalent DMV visibility and confirm the collector can read SQL text/query plan metadata.';
  }

  if (normalizedMetric.includes('always')) {
    return 'For Always On failures, verify the instance participates in an availability group and the collector login can read HADR DMVs.';
  }

  if (normalizedMetric.includes('replication')) {
    return 'For Replication failures, verify replication is configured and the collector can read distribution/agent metadata on the relevant instance.';
  }

  return 'Verify the metric-specific source permissions described in the collector README, then rerun only after the connection and permission checks pass.';
}

function getLogReuseWaitAction(logReuseWait) {
  switch (String(logReuseWait ?? '').toUpperCase()) {
    case 'LOG_BACKUP':
      return 'This usually means log backups are missing or failing; fix the log backup chain/job before expecting log truncation.';
    case 'ACTIVE_TRANSACTION':
      return 'This means an open transaction is preventing truncation; use the long-running transaction and blocking evidence first.';
    case 'AVAILABILITY_REPLICA':
      return 'This means Always On synchronization is holding log truncation; fix unhealthy or lagging replicas first.';
    case 'REPLICATION':
      return 'This means replication has not consumed log records; fix Log Reader/Distribution agent health and backlog first.';
    case 'NOTHING':
      return 'A NOTHING wait means the log may be growing from active workload or recent autogrowth; validate current usage and backup cadence.';
    default:
      return 'Use the captured log reuse wait to decide whether the blocker is backups, transactions, Always On, replication, or another SQL Server dependency.';
  }
}

function getWorstBlockedSession(rows) {
  return [...rows].sort((left, right) => Number(right?.waitDurationMs ?? 0) - Number(left?.waitDurationMs ?? 0))[0] ?? null;
}

function getLongestTransaction(rows) {
  return [...rows].sort((left, right) => Number(right?.durationMinutes ?? 0) - Number(left?.durationMinutes ?? 0))[0] ?? null;
}

function truncateText(value, maxLength) {
  const text = String(value ?? '').replace(/\s+/g, ' ').trim();
  return text.length > maxLength ? `${text.slice(0, maxLength - 3)}...` : text;
}

function formatGb(value) {
  return formatStorageFromGb(value);
}

function formatMb(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return formatStorageFromGb(Number(value) / 1024);
}

function formatKb(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return formatStorageFromGb(Number(value) / 1024 / 1024);
}

function formatDaysRemaining(value) {
  return formatRemainingTimeFromDays(value, 'unknown');
}

function formatPercent(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return `${Number(value).toLocaleString(undefined, {
    maximumFractionDigits: 2,
    minimumFractionDigits: 0
  })}%`;
}

function formatHours(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  const numericValue = Number(value);
  return `${numericValue.toLocaleString(undefined, {
    maximumFractionDigits: numericValue < 10 ? 1 : 0,
    minimumFractionDigits: 0
  })} ${Math.round(numericValue * 10) / 10 === 1 ? 'hour' : 'hours'}`;
}

function formatMs(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  const numericValue = Number(value);
  if (numericValue >= 60000) {
    return `${(numericValue / 60000).toLocaleString(undefined, {
      maximumFractionDigits: 1,
      minimumFractionDigits: 0
    })} minutes`;
  }

  if (numericValue >= 1000) {
    return `${(numericValue / 1000).toLocaleString(undefined, {
      maximumFractionDigits: 1,
      minimumFractionDigits: 0
    })} seconds`;
  }

  return `${numericValue.toLocaleString()} ms`;
}

function formatSeconds(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  const numericValue = Number(value);
  if (numericValue >= 3600) {
    return `${(numericValue / 3600).toLocaleString(undefined, {
      maximumFractionDigits: 1,
      minimumFractionDigits: 0
    })} hours`;
  }

  if (numericValue >= 60) {
    return `${(numericValue / 60).toLocaleString(undefined, {
      maximumFractionDigits: 1,
      minimumFractionDigits: 0
    })} minutes`;
  }

  return `${numericValue.toLocaleString()} seconds`;
}

function formatDateEvidence(value) {
  if (value === null || value === undefined || value === '') {
    return '-';
  }

  return String(value).replace('T', ' ');
}

function buildAlertEmailSubject(alert) {
  return `[${formatDetailValue(alert.severity)}] ${formatDetailValue(alert.alertType)} on ${formatDetailValue(alert.serverName)}${alert.databaseName ? `/${alert.databaseName}` : ''}`;
}

function describeEmailIssue(alert, details) {
  const target = describeAlertTarget(alert, details);

  switch (String(alert.alertType ?? details?.category ?? '').toLowerCase()) {
    case 'fullrecoverynologbackup':
      return `a log backup coverage gap on ${target}`;
    case 'logfileexhaustionrisk':
      return `transaction log exhaustion risk on ${target}`;
    case 'longrunningtransaction':
      return `a long-running transaction on ${target}`;
    case 'blockingchain':
      return `a blocking chain on ${target}`;
    case 'activetransactionlogreusewait':
      return `log truncation blocked by an active transaction on ${target}`;
    case 'alwaysonhealthissue':
    case 'alwaysonlogreusewait':
      return `an Always On health/log-truncation issue on ${target}`;
    case 'replicationagentissue':
    case 'replicationlogreusewait':
      return `a replication health/log-truncation issue on ${target}`;
    case 'tempdbusage':
      return `high TempDB usage on ${target}`;
    case 'diskspacelow':
      return `low disk space on ${target}`;
    case 'backupgrowth':
      return `unusual backup growth on ${target}`;
    case 'capacityrisk':
      return `capacity risk on ${target}`;
    default:
      return `a ${formatDetailValue(alert.severity)} ${formatDetailValue(alert.alertType)} alert on ${target}`;
  }
}

function getEmailImpactSummary(alert, details) {
  const alertType = String(alert.alertType ?? details?.category ?? '').toLowerCase();

  if (alertType === 'fullrecoverynologbackup') {
    const logText = `Current log size is ${formatGb(details?.currentLogSizeGb)} and log reuse wait is ${formatDetailValue(details?.logReuseWait)}.`;
    if (String(details?.logReuseWait ?? '').toUpperCase() === 'NOTHING') {
      return `${logText} This is mainly a recoverability and RPO risk right now: the database is in FULL recovery, but the repository has not observed a recent log backup. Without recurring log backups, point-in-time restore coverage may be missing and the log can grow quickly when workload increases.`;
    }

    return `${logText} FULL recovery requires regular log backups. Missing or failing log backups can break RPO expectations and allow the transaction log to grow until storage or file limits are reached.`;
  }

  if (alertType === 'logfileexhaustionrisk') {
    return `The transaction log is using ${formatPercent(details?.percentOfEffectiveCap)} of its effective cap with ${formatGb(details?.remainingToCapGb)} remaining. The effective cap accounts for configured max size, SQL Server's practical log-file cap, and observed disk headroom.`;
  }

  if (alertType === 'longrunningtransaction') {
    return `Session ${formatDetailValue(details?.sessionId)} has an open transaction for ${formatDurationMinutes(details?.durationMinutes)} minutes. Long transactions can hold locks and prevent log truncation, especially in FULL recovery.`;
  }

  if (alertType === 'blockingchain') {
    return `Lead blocker session ${formatDetailValue(details?.leadBlockerSessionId)} is blocking ${formatDetailValue(details?.blockedSessionCount)} session(s), with max wait ${formatMs(details?.maxBlockedWaitMs)}. This can cause application timeouts and downstream workload buildup.`;
  }

  if (alertType === 'activetransactionlogreusewait') {
    return `SQL Server reports log reuse wait ${formatDetailValue(details?.logReuseWait)}. The log cannot truncate until the active transaction or blocker clears.`;
  }

  if (alertType === 'alwaysonhealthissue' || alertType === 'alwaysonlogreusewait') {
    return `Always On evidence shows replica/database synchronization health needs review. Unhealthy or lagging replicas can delay failover readiness and hold log truncation.`;
  }

  if (alertType === 'replicationagentissue' || alertType === 'replicationlogreusewait') {
    return `Replication evidence shows agent or distribution health needs review. Replication failures can delay downstream data delivery and prevent publisher log truncation.`;
  }

  if (alertType === 'tempdbusage') {
    return `TempDB is ${formatPercent(details?.usedPercent)} used. High TempDB consumption can cause query failures, application errors, and instance-wide pressure.`;
  }

  if (alertType === 'diskspacelow') {
    return `Volume ${formatDetailValue(details?.volumeMountPoint)} has ${formatGb(details?.availableGb)} available and is ${formatPercent(details?.usedPercent)} used. Low disk space can prevent data/log growth and interrupt SQL Server operations.`;
  }

  if (alertType === 'backupgrowth') {
    return `${formatDetailValue(details?.backupType)} backup size increased to ${formatGb(details?.backupSizeGb)} versus a recent average of ${formatGb(details?.averageBackupSizeGb)}. This may affect backup duration, storage, and retention capacity.`;
  }

  if (alertType === 'capacityrisk') {
    return `Forecast shows ${formatGb(details?.availableSpaceGb)} available and estimated time remaining ${formatDaysRemaining(details?.estimatedDaysRemaining)}. Capacity exhaustion can stop data growth or cause application failures.`;
  }

  return 'Please review the dashboard evidence and confirm ownership, severity, and business impact.';
}

function selectEmailActionSteps(alert, details, steps) {
  const alertType = String(alert.alertType ?? details?.category ?? '').toLowerCase();

  if (alertType === 'fullrecoverynologbackup') {
    return compactSteps([
      'Confirm whether this database should remain in FULL recovery for point-in-time restore, Always On, replication, or compliance.',
      hasRenderableDetail(details?.lastLogBackupFinishDate)
        ? 'If FULL recovery is required, take or verify an immediate log backup and investigate why the regular log backup interval was missed.'
        : 'If FULL recovery is required and no valid backup chain exists, take a full backup first, then start recurring log backups.',
      'Fix or create the recurring log backup job and validate destination capacity, credentials, compression/encryption settings, and monitoring.',
      'If FULL recovery is not required, get approval and switch to SIMPLE recovery during a change window.',
      'Rerun the collector and confirm a recent log backup appears in the dashboard or the recovery model decision is reflected.'
    ]);
  }

  return steps.slice(0, 6);
}

function getEmailSafetyNote(alertType) {
  const normalizedType = String(alertType ?? '').toLowerCase();

  if (['longrunningtransaction', 'blockingchain', 'activetransactionlogreusewait'].includes(normalizedType)) {
    return 'Please confirm business impact and rollback risk before killing sessions or forcing transaction rollback.';
  }

  if (['fullrecoverynologbackup', 'logfileexhaustionrisk'].includes(normalizedType)) {
    return 'Please confirm recovery requirements before changing recovery model, backup cadence, file growth, max size, or storage layout.';
  }

  return 'Please confirm application ownership and business impact before making production-impacting changes.';
}

function buildAlertEmailBody(alert, details, message, steps, attachments = [], timeZone) {
  const evidenceLines = getEmailEvidenceLines(alert, details);
  const actionLines = selectEmailActionSteps(alert, details, steps).map((step, index) => `${index + 1}. ${step}`);
  const hasSqlAttachment = attachments.some((attachment) => attachment.fileName.toLowerCase().endsWith('.sql'));
  const hasPlanAttachment = attachments.some((attachment) => attachment.fileName.toLowerCase().endsWith('.sqlplan'));
  const attachmentSection = attachments.length > 0
    ? [
        '',
        'Evidence files prepared:',
        ...attachments.map((attachment) => `- ${attachment.fileName}: ${attachment.description}`),
        '',
        'Attach the downloaded evidence files before sending. .sql files contain captured query text; .sqlplan files can be opened in SSMS or another SQL Server plan viewer.'
      ]
    : [];

  return [
    'Hi team,',
    '',
    `DBA Capacity detected ${describeEmailIssue(alert, details)}.`,
    '',
    'Why this matters:',
    getEmailImpactSummary(alert, details),
    '',
    'Alert summary:',
    `- Environment: ${formatDetailValue(alert.environment)}`,
    `- Server: ${formatDetailValue(alert.serverName)}`,
    `- Database: ${formatDetailValue(alert.databaseName)}`,
    `- Alert type: ${formatDetailValue(alert.alertType)}`,
    `- Severity: ${formatDetailValue(alert.severity)}`,
    `- Status: ${alert.isResolved ? 'Resolved' : 'Active'}`,
    `- Detected: ${formatDateTime(alert.alertTime, timeZone)}`,
    `- Message: ${message}`,
    ...(hasSqlAttachment ? ['- SQL text captured: Yes, prepared as .sql evidence'] : []),
    ...(hasPlanAttachment ? ['- Query plan captured: Yes, prepared as .sqlplan evidence'] : []),
    '',
    'Relevant evidence:',
    ...evidenceLines.map((line) => `- ${line}`),
    ...attachmentSection,
    '',
    'Recommended next actions:',
    ...actionLines,
    '',
    getEmailSafetyNote(alert.alertType),
    '',
    'Regards,',
    'DBA Team'
  ].join('\n');
}

function getEmailEvidenceLines(alert, details) {
  const lines = [];

  if (details?.leadBlockerSessionId) {
    lines.push(`Lead blocker session: ${details.leadBlockerSessionId}`);
  }
  if (details?.blockedSessionCount) {
    lines.push(`Blocked sessions: ${details.blockedSessionCount}`);
  }
  if (details?.sessionId) {
    lines.push(`Session id: ${details.sessionId}`);
  }
  if (details?.loginName || details?.leadBlockerLoginName) {
    lines.push(`Login: ${details.loginName || details.leadBlockerLoginName}`);
  }
  if (details?.hostName || details?.leadBlockerHostName) {
    lines.push(`Host: ${details.hostName || details.leadBlockerHostName}`);
  }
  if (details?.durationMinutes) {
    lines.push(`Duration: ${formatDurationMinutes(details.durationMinutes)} minutes`);
  }
  if (details?.currentLogSizeGb) {
    lines.push(`Current log size: ${formatGb(details.currentLogSizeGb)}`);
  }
  if (details?.usedLogGb) {
    lines.push(`Used log: ${formatGb(details.usedLogGb)}`);
  }
  if (details?.remainingToCapGb) {
    lines.push(`Remaining log headroom: ${formatGb(details.remainingToCapGb)}`);
  }
  if (details?.logReuseWait) {
    lines.push(`Log reuse wait: ${details.logReuseWait}`);
  }
  if (details?.recoveryModel) {
    lines.push(`Recovery model: ${details.recoveryModel}`);
  }
  if (details?.lastLogBackupFinishDate) {
    lines.push(`Last observed log backup: ${formatDateEvidence(details.lastLogBackupFinishDate)}`);
  }
  if (details?.hoursSinceLastLogBackup) {
    lines.push(`Hours since last observed log backup: ${formatHours(details.hoursSinceLastLogBackup)}`);
  }
  if (details?.lastLogBackupFinishDate === null || details?.lastLogBackupFinishDate === undefined) {
    if (String(alert.alertType ?? details?.category ?? '').toLowerCase() === 'fullrecoverynologbackup') {
      lines.push('Last observed log backup: none in collected backup history');
    }
  }
  if (details?.availabilityGroupName) {
    lines.push(`Availability group: ${details.availabilityGroupName}`);
  }
  if (details?.replicaServerName) {
    lines.push(`Replica: ${details.replicaServerName}`);
  }
  if (details?.agentName) {
    lines.push(`Replication agent: ${details.agentName}`);
  }
  if (details?.sourceScripts || alert.sourceScript) {
    lines.push(`Source scripts: ${formatDetailValue(details?.sourceScripts || alert.sourceScript)}`);
  }

  if (lines.length === 0) {
    lines.push('Structured evidence is available in the dashboard More info panel.');
  }

  return lines;
}

function formatLockObject(lock) {
  const objectName = String(lock?.objectName ?? '').trim();

  if (objectName && objectName !== '.') {
    return objectName;
  }

  return lock?.pageId || lock?.resourceDescription || lock?.resourceAssociatedEntityId || '-';
}

function formatLockResourceDetail(lock) {
  if (!lock || typeof lock !== 'object') {
    return '-';
  }

  const parts = [];
  if (lock.pageId) {
    parts.push(`Page ${lock.pageId}`);
  }
  if (lock.fileId) {
    parts.push(`File ${lock.fileId}`);
  }
  if (lock.resourceDescription) {
    parts.push(lock.resourceDescription);
  }
  if (lock.resourceAssociatedEntityId) {
    parts.push(`Entity ${lock.resourceAssociatedEntityId}`);
  }

  return parts.length > 0 ? [...new Set(parts)].join(' | ') : '-';
}

function formatDurationMinutes(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '-';
  }

  return Number(value).toLocaleString(undefined, {
    maximumFractionDigits: 2,
    minimumFractionDigits: 2
  });
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

function formatSqlTextLabel(path) {
  return (
    formatQueryPlanLabel(path)
      .replace(/\s*Sql Text$/i, ' SQL text')
      .replace(/\s+/g, ' ')
      .trim() || 'SQL text'
  );
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
