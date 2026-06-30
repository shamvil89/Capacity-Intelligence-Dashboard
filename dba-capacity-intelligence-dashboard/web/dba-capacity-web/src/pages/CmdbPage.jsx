import { Download, Pencil, Plus, Trash2, Upload } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import CmdbEntryModal from '../components/CmdbEntryModal.jsx';
import ColumnFilter from '../components/ColumnFilter.jsx';
import DataState from '../components/DataState.jsx';
import SortableHeader from '../components/SortableHeader.jsx';
import { useAppAuth } from '../auth/AuthProvider.jsx';
import { containsText, getSelectedFilterFields, nextSortState, sortRows } from '../components/tableUtils.js';
import { api } from '../services/api.js';

const cmdbFilterColumns = [
  { key: 'applicationName', label: 'Application' },
  { key: 'environment', label: 'Environment' },
  { key: 'serverName', label: 'Server' },
  { key: 'databaseName', label: 'Database' },
  { key: 'prodOpsTeamEmail', label: 'ProdOps' },
  { key: 'applicationOwnerEmail', label: 'App Owner' },
  { key: 'businessOwnerEmail', label: 'Business Owner' },
  { key: 'supportDlEmail', label: 'Support DL' },
  { key: 'escalationDlEmail', label: 'Escalation DL' },
  { key: 'serviceNowGroup', label: 'ServiceNow' },
  { key: 'criticality', label: 'Criticality' },
  { key: 'notes', label: 'Notes' }
];

const csvHeaders = [
  'application_name',
  'environment',
  'server_name',
  'database_name',
  'prodops_team_email',
  'application_owner_email',
  'business_owner_email',
  'support_dl_email',
  'escalation_dl_email',
  'servicenow_group',
  'criticality',
  'application_url',
  'notes',
  'is_active'
];

export default function CmdbPage() {
  const { canEdit } = useAppAuth();
  const fileInputRef = useRef(null);
  const [entries, setEntries] = useState([]);
  const [containsFilter, setContainsFilter] = useState('');
  const [filterColumns, setFilterColumns] = useState(cmdbFilterColumns.map((column) => column.key));
  const [sortState, setSortState] = useState({ key: 'applicationName', direction: 'asc' });
  const [editor, setEditor] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [status, setStatus] = useState('');
  const [error, setError] = useState('');

  const loadEntries = useCallback(async () => {
    setIsLoading(true);
    setError('');

    try {
      const rows = await api.getCmdbEntries();
      setEntries(rows ?? []);
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadEntries();
  }, [loadEntries]);

  const visibleEntries = useMemo(() => {
    const activeFilterFields = getSelectedFilterFields(cmdbFilterColumns, filterColumns);
    const filteredRows = entries.filter((item) => containsText(item, activeFilterFields, containsFilter));

    return sortRows(filteredRows, sortState, {
      applicationUpdatedAt: 'date',
      mappingUpdatedAt: 'date'
    });
  }, [containsFilter, entries, filterColumns, sortState]);

  function handleSort(key) {
    setSortState((currentState) => nextSortState(currentState, key));
  }

  async function handleSaved() {
    setEditor(null);
    await loadEntries();
  }

  async function handleDeleteMapping(entry) {
    if (!canEdit) {
      setStatus('Editor role is required to delete CMDB mappings.');
      return;
    }

    if (!entry.mappingId) {
      return;
    }

    const confirmed = window.confirm(`Remove mapping for ${entry.serverName}/${entry.databaseName}?`);
    if (!confirmed) {
      return;
    }

    try {
      setStatus('');
      await api.deleteCmdbMapping(entry.mappingId);
      await loadEntries();
    } catch (err) {
      setStatus(err.message);
    }
  }

  async function handleDeleteApplication(entry) {
    if (!canEdit) {
      setStatus('Editor role is required to delete CMDB applications.');
      return;
    }

    const confirmed = window.confirm(`Delete application '${entry.applicationName}' and all of its database mappings?`);
    if (!confirmed) {
      return;
    }

    try {
      setStatus('');
      await api.deleteCmdbApplication(entry.applicationId);
      await loadEntries();
    } catch (err) {
      setStatus(err.message);
    }
  }

  function handleExportCsv() {
    const csv = buildCsv(entries);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `dba-capacity-cmdb-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  async function handleImportFile(event) {
    const file = event.target.files?.[0];
    event.target.value = '';

    if (!file) {
      return;
    }

    if (!canEdit) {
      setStatus('Editor role is required to import CMDB rows.');
      return;
    }

    try {
      setStatus('Importing...');
      const text = await file.text();
      const rows = parseCmdbCsv(text);
      const importedRows = await api.importCmdbEntries(rows);
      setEntries(importedRows ?? []);
      setStatus(`Imported ${rows.length} row${rows.length === 1 ? '' : 's'}`);
      window.setTimeout(() => setStatus(''), 2200);
    } catch (err) {
      setStatus(err.message);
    }
  }

  return (
    <section className="page-stack">
      <div className="toolbar-row">
        <div>
          <h2>CMDB</h2>
          <p className="subtle">Application ownership and contact mapping for monitored databases.</p>
        </div>
        <div className="dashboard-toolbar-actions">
          <button type="button" className="secondary-action" onClick={() => setEditor({ entry: null })} disabled={!canEdit} title={canEdit ? 'New CMDB entry' : 'Editor role required'}>
            <Plus aria-hidden="true" size={14} />
            New entry
          </button>
          <button type="button" className="secondary-action" onClick={handleExportCsv} disabled={entries.length === 0}>
            <Download aria-hidden="true" size={14} />
            Export CSV
          </button>
          <button type="button" className="secondary-action" onClick={() => fileInputRef.current?.click()} disabled={!canEdit} title={canEdit ? 'Import CMDB CSV' : 'Editor role required'}>
            <Upload aria-hidden="true" size={14} />
            Import CSV
          </button>
          <input ref={fileInputRef} className="hidden-file-input" type="file" accept=".csv,text/csv" onChange={handleImportFile} />
        </div>
      </div>

      {status ? <div className={status.startsWith('Imported') ? 'state-box cmdb-status success' : 'state-box cmdb-status'}>{status}</div> : null}

      <DataState isLoading={isLoading} error={error} isEmpty={entries.length === 0}>
        <div className="table-panel">
          <div className="table-panel-header">
            <h3>Application Database Mapping</h3>
            <span>{visibleEntries.length} rows</span>
          </div>

          <div className="table-controls">
            <ColumnFilter
              columns={cmdbFilterColumns}
              selectedColumns={filterColumns}
              value={containsFilter}
              onChange={setContainsFilter}
              onSelectedColumnsChange={setFilterColumns}
              placeholder="Application, owner, DL, server, database, notes"
            />
          </div>

          <DataState isLoading={false} error="" isEmpty={visibleEntries.length === 0}>
            <div className="table-scroll">
              <table className="cmdb-table">
                <thead>
                  <tr>
                    <th><SortableHeader label="Application" sortKey="applicationName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Environment" sortKey="environment" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Server" sortKey="serverName" sortState={sortState} onSort={handleSort} /></th>
                    <th><SortableHeader label="Database" sortKey="databaseName" sortState={sortState} onSort={handleSort} /></th>
                    <th>ProdOps</th>
                    <th>App Owner</th>
                    <th>Business Owner</th>
                    <th>Support DL</th>
                    <th>Escalation DL</th>
                    <th>Criticality</th>
                    <th>ServiceNow</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {visibleEntries.map((entry) => (
                    <tr key={`${entry.applicationId}-${entry.mappingId ?? 'app'}`}>
                      <td>
                        <strong>{entry.applicationName}</strong>
                        {entry.applicationUrl ? <a className="setting-key" href={entry.applicationUrl} target="_blank" rel="noreferrer">Application URL</a> : null}
                      </td>
                      <td>{entry.environment || '-'}</td>
                      <td>{entry.serverName || '-'}</td>
                      <td>{entry.databaseName || '-'}</td>
                      <td>{entry.prodOpsTeamEmail || '-'}</td>
                      <td>{entry.applicationOwnerEmail || '-'}</td>
                      <td>{entry.businessOwnerEmail || '-'}</td>
                      <td>{entry.supportDlEmail || '-'}</td>
                      <td>{entry.escalationDlEmail || '-'}</td>
                      <td>{entry.criticality || '-'}</td>
                      <td>{entry.serviceNowGroup || '-'}</td>
                      <td>
                        <div className="row-actions">
                          <button type="button" className="secondary-action" onClick={() => setEditor({ entry })} disabled={!canEdit} title={canEdit ? 'Edit CMDB row' : 'Editor role required'}>
                            <Pencil aria-hidden="true" size={14} />
                            Edit
                          </button>
                          {entry.mappingId ? (
                            <button type="button" className="secondary-action danger-action" onClick={() => handleDeleteMapping(entry)} disabled={!canEdit}>
                              <Trash2 aria-hidden="true" size={14} />
                              Mapping
                            </button>
                          ) : null}
                          <button type="button" className="secondary-action danger-action" onClick={() => handleDeleteApplication(entry)} disabled={!canEdit}>
                            <Trash2 aria-hidden="true" size={14} />
                            App
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

      {editor ? (
        <CmdbEntryModal
          entry={editor.entry}
          title={editor.entry ? `Edit ${editor.entry.applicationName}` : 'New CMDB entry'}
          onClose={() => setEditor(null)}
          onSaved={handleSaved}
        />
      ) : null}
    </section>
  );
}

function buildCsv(entries) {
  const lines = [
    csvHeaders.join(','),
    ...entries.map((entry) => csvHeaders.map((header) => escapeCsv(resolveExportValue(entry, header))).join(','))
  ];

  return `${lines.join('\r\n')}\r\n`;
}

function resolveExportValue(entry, header) {
  const map = {
    application_name: entry.applicationName,
    environment: entry.environment,
    server_name: entry.serverName,
    database_name: entry.databaseName,
    prodops_team_email: entry.prodOpsTeamEmail,
    application_owner_email: entry.applicationOwnerEmail,
    business_owner_email: entry.businessOwnerEmail,
    support_dl_email: entry.supportDlEmail,
    escalation_dl_email: entry.escalationDlEmail,
    servicenow_group: entry.serviceNowGroup,
    criticality: entry.criticality,
    application_url: entry.applicationUrl,
    notes: entry.notes,
    is_active: entry.isActive === false ? 'false' : 'true'
  };

  return map[header] ?? '';
}

function escapeCsv(value) {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function parseCmdbCsv(text) {
  const rows = parseCsv(text);
  if (rows.length < 2) {
    throw new Error('CSV must contain a header row and at least one data row.');
  }

  const headers = rows[0].map(normalizeHeader);
  return rows.slice(1)
    .filter((row) => row.some((value) => String(value ?? '').trim()))
    .map((row) => {
      const record = Object.fromEntries(headers.map((header, index) => [header, row[index] ?? '']));
      return {
        applicationName: pick(record, 'application_name', 'application'),
        environment: pick(record, 'environment'),
        serverName: pick(record, 'server_name', 'server'),
        databaseName: pick(record, 'database_name', 'database'),
        prodOpsTeamEmail: pick(record, 'prodops_team_email', 'prodops_email', 'prod_ops_email'),
        applicationOwnerEmail: pick(record, 'application_owner_email', 'app_owner_email', 'owner_email'),
        businessOwnerEmail: pick(record, 'business_owner_email'),
        supportDlEmail: pick(record, 'support_dl_email', 'support_email'),
        escalationDlEmail: pick(record, 'escalation_dl_email', 'escalation_email'),
        serviceNowGroup: pick(record, 'servicenow_group', 'service_now_group'),
        criticality: pick(record, 'criticality'),
        applicationUrl: pick(record, 'application_url', 'app_url', 'url'),
        notes: pick(record, 'notes'),
        isActive: parseBoolean(pick(record, 'is_active', 'active'))
      };
    });
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (char === '"') {
      if (inQuotes && nextChar === '"') {
        field += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === ',' && !inQuotes) {
      row.push(field);
      field = '';
      continue;
    }

    if ((char === '\n' || char === '\r') && !inQuotes) {
      if (char === '\r' && nextChar === '\n') {
        index += 1;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      continue;
    }

    field += char;
  }

  if (field || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

function normalizeHeader(value) {
  return String(value ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');
}

function pick(record, ...keys) {
  const key = keys.find((candidate) => record[candidate] !== undefined);
  const value = key ? record[key] : '';
  return String(value ?? '').trim() || null;
}

function parseBoolean(value) {
  if (value === null || value === undefined || value === '') {
    return true;
  }

  return !['0', 'false', 'no', 'inactive'].includes(String(value).trim().toLowerCase());
}
