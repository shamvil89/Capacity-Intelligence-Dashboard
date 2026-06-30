import { Save, X } from 'lucide-react';
import { useEffect, useState } from 'react';
import { api } from '../services/api.js';

const emptyForm = {
  applicationId: null,
  mappingId: null,
  applicationName: '',
  environment: '',
  serverName: '',
  databaseName: '',
  isActive: true,
  prodOpsTeamEmail: '',
  applicationOwnerEmail: '',
  businessOwnerEmail: '',
  supportDlEmail: '',
  escalationDlEmail: '',
  serviceNowGroup: '',
  criticality: '',
  applicationUrl: '',
  notes: ''
};

export default function CmdbEntryModal({
  entry,
  defaults = {},
  lockDatabaseFields = false,
  title = 'Application CMDB',
  onClose,
  onSaved
}) {
  const [form, setForm] = useState(() => toForm(entry, defaults));
  const [status, setStatus] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    setForm(toForm(entry, defaults));
    setStatus('');
  }, [entry, defaults]);

  function updateField(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setStatus('');
  }

  async function handleSubmit(event) {
    event.preventDefault();

    if (!form.applicationName.trim()) {
      setStatus('Application name is required.');
      return;
    }

    if (Boolean(form.serverName.trim()) !== Boolean(form.databaseName.trim())) {
      setStatus('Server and database must both be set when creating a mapping.');
      return;
    }

    setIsSaving(true);
    setStatus('Saving...');

    try {
      const saved = await api.upsertCmdbEntry(toPayload(form));
      setStatus('Saved');
      onSaved?.(saved);
      window.setTimeout(() => setStatus(''), 1800);
    } catch (err) {
      setStatus(err.message);
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="modal-panel cmdb-modal" role="dialog" aria-modal="true" aria-labelledby="cmdb-editor-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <div>
            <p className="eyebrow">CMDB</p>
            <h3 id="cmdb-editor-title">{title}</h3>
          </div>
          <button type="button" className="icon-action" aria-label="Close CMDB editor" onClick={onClose}>
            <X aria-hidden="true" size={18} />
          </button>
        </div>

        <form className="modal-body cmdb-form" onSubmit={handleSubmit}>
          <div className="cmdb-form-grid">
            <CmdbField label="Application name" value={form.applicationName} onChange={(value) => updateField('applicationName', value)} required />
            <CmdbField label="Environment" value={form.environment} onChange={(value) => updateField('environment', value)} disabled={lockDatabaseFields} />
            <CmdbField label="Server" value={form.serverName} onChange={(value) => updateField('serverName', value)} disabled={lockDatabaseFields} />
            <CmdbField label="Database" value={form.databaseName} onChange={(value) => updateField('databaseName', value)} disabled={lockDatabaseFields} />
            <CmdbField label="ProdOps team email" value={form.prodOpsTeamEmail} onChange={(value) => updateField('prodOpsTeamEmail', value)} />
            <CmdbField label="Application owner email" value={form.applicationOwnerEmail} onChange={(value) => updateField('applicationOwnerEmail', value)} />
            <CmdbField label="Business owner email" value={form.businessOwnerEmail} onChange={(value) => updateField('businessOwnerEmail', value)} />
            <CmdbField label="Support DL email" value={form.supportDlEmail} onChange={(value) => updateField('supportDlEmail', value)} />
            <CmdbField label="Escalation DL email" value={form.escalationDlEmail} onChange={(value) => updateField('escalationDlEmail', value)} />
            <CmdbField label="ServiceNow group" value={form.serviceNowGroup} onChange={(value) => updateField('serviceNowGroup', value)} />
            <CmdbField label="Criticality" value={form.criticality} onChange={(value) => updateField('criticality', value)} />
            <CmdbField label="Application URL" value={form.applicationUrl} onChange={(value) => updateField('applicationUrl', value)} type="url" />
          </div>

          <label className="cmdb-field cmdb-field-wide">
            <span>Notes</span>
            <textarea value={form.notes} onChange={(event) => updateField('notes', event.target.value)} rows={4} />
          </label>

          <label className="cmdb-checkbox">
            <input
              type="checkbox"
              checked={form.isActive}
              onChange={(event) => updateField('isActive', event.target.checked)}
            />
            <span>Active database mapping</span>
          </label>

          <div className="modal-actions">
            {status ? <span className={status === 'Saved' ? 'setting-status success' : 'setting-status'}>{status}</span> : null}
            <button type="button" className="secondary-action" onClick={onClose}>Cancel</button>
            <button type="submit" className="secondary-action" disabled={isSaving}>
              <Save aria-hidden="true" size={14} />
              Save
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}

function CmdbField({ label, value, onChange, type = 'text', required = false, disabled = false }) {
  return (
    <label className="cmdb-field">
      <span>{label}</span>
      <input
        type={type}
        value={value}
        required={required}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function toForm(entry, defaults) {
  return {
    ...emptyForm,
    applicationId: entry?.applicationId ?? null,
    mappingId: entry?.mappingId ?? null,
    applicationName: entry?.applicationName ?? '',
    environment: entry?.environment ?? defaults?.environment ?? '',
    serverName: entry?.serverName ?? defaults?.serverName ?? '',
    databaseName: entry?.databaseName ?? defaults?.databaseName ?? '',
    isActive: entry?.isActive ?? true,
    prodOpsTeamEmail: entry?.prodOpsTeamEmail ?? '',
    applicationOwnerEmail: entry?.applicationOwnerEmail ?? '',
    businessOwnerEmail: entry?.businessOwnerEmail ?? '',
    supportDlEmail: entry?.supportDlEmail ?? '',
    escalationDlEmail: entry?.escalationDlEmail ?? '',
    serviceNowGroup: entry?.serviceNowGroup ?? '',
    criticality: entry?.criticality ?? '',
    applicationUrl: entry?.applicationUrl ?? '',
    notes: entry?.notes ?? ''
  };
}

function toPayload(form) {
  return {
    applicationId: form.applicationId,
    mappingId: form.mappingId,
    applicationName: clean(form.applicationName),
    environment: clean(form.environment),
    serverName: clean(form.serverName),
    databaseName: clean(form.databaseName),
    isActive: form.isActive,
    prodOpsTeamEmail: clean(form.prodOpsTeamEmail),
    applicationOwnerEmail: clean(form.applicationOwnerEmail),
    businessOwnerEmail: clean(form.businessOwnerEmail),
    supportDlEmail: clean(form.supportDlEmail),
    escalationDlEmail: clean(form.escalationDlEmail),
    serviceNowGroup: clean(form.serviceNowGroup),
    criticality: clean(form.criticality),
    applicationUrl: clean(form.applicationUrl),
    notes: clean(form.notes)
  };
}

function clean(value) {
  const trimmed = String(value ?? '').trim();
  return trimmed || null;
}
