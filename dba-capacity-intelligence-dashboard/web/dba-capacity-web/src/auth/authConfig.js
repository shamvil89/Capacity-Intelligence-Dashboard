export const authEnabled = String(import.meta.env.VITE_AUTH_ENABLED ?? 'false').toLowerCase() === 'true';

const tenantId = import.meta.env.VITE_ENTRA_TENANT_ID ?? '';
const configuredAuthority = import.meta.env.VITE_ENTRA_AUTHORITY ?? '';
const clientId = import.meta.env.VITE_ENTRA_CLIENT_ID ?? '';
const apiScope = import.meta.env.VITE_ENTRA_API_SCOPE ?? '';

export const authConfigErrors = authEnabled
  ? [
      !clientId ? 'VITE_ENTRA_CLIENT_ID is required when VITE_AUTH_ENABLED=true.' : '',
      !tenantId && !configuredAuthority ? 'VITE_ENTRA_TENANT_ID or VITE_ENTRA_AUTHORITY is required when VITE_AUTH_ENABLED=true.' : '',
      !apiScope ? 'VITE_ENTRA_API_SCOPE is required when VITE_AUTH_ENABLED=true.' : ''
    ].filter(Boolean)
  : [];

export const msalConfig = {
  auth: {
    clientId,
    authority: configuredAuthority || (tenantId ? `https://login.microsoftonline.com/${tenantId}` : ''),
    redirectUri: window.location.origin + window.location.pathname,
    postLogoutRedirectUri: window.location.origin + window.location.pathname
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false
  }
};

export const loginRequest = {
  scopes: apiScope ? [apiScope] : []
};

export const roleConfig = {
  admin: parseRoleList(import.meta.env.VITE_RBAC_ADMIN_ROLES, ['DBA.Capacity.Admin']),
  editor: parseRoleList(import.meta.env.VITE_RBAC_EDITOR_ROLES, ['DBA.Capacity.Editor']),
  reader: parseRoleList(import.meta.env.VITE_RBAC_READER_ROLES, ['DBA.Capacity.Reader'])
};

export function parseRoleList(value, fallback) {
  const roles = String(value ?? '')
    .split(/[;,]/)
    .map((role) => role.trim())
    .filter(Boolean);

  return roles.length > 0 ? roles : fallback;
}
