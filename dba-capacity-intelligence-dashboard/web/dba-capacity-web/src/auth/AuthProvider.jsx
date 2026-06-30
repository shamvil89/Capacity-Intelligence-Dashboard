import { InteractionRequiredAuthError, InteractionStatus, PublicClientApplication } from '@azure/msal-browser';
import { MsalProvider, useIsAuthenticated, useMsal } from '@azure/msal-react';
import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { configureApiAuth } from '../services/api.js';
import { authConfigErrors, authEnabled, loginRequest, msalConfig, roleConfig } from './authConfig.js';

const AuthContext = createContext({
  authEnabled: false,
  userName: 'Local user',
  roles: [],
  canRead: true,
  canEdit: true,
  canAdmin: true,
  signIn: () => {},
  signOut: () => {}
});

const msalInstance = authEnabled && authConfigErrors.length === 0
  ? new PublicClientApplication(msalConfig)
  : null;

export function AppAuthProvider({ children }) {
  const [isReady, setIsReady] = useState(!msalInstance);
  const [startupError, setStartupError] = useState('');

  useEffect(() => {
    if (!msalInstance) {
      return undefined;
    }

    let isMounted = true;
    msalInstance
      .initialize()
      .then(() => {
        if (isMounted) {
          setIsReady(true);
        }
      })
      .catch((err) => {
        if (isMounted) {
          setStartupError(err.message || 'Unable to initialize Microsoft Entra sign-in.');
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  if (!authEnabled) {
    configureApiAuth(null);
    return (
      <AuthContext.Provider value={disabledAuthContext}>
        {children}
      </AuthContext.Provider>
    );
  }

  if (authConfigErrors.length > 0) {
    return <AuthStatePage title="SSO configuration is incomplete" messages={authConfigErrors} />;
  }

  if (startupError) {
    return <AuthStatePage title="SSO could not start" messages={[startupError]} />;
  }

  if (!isReady) {
    return <div className="route-loading">Preparing sign-in...</div>;
  }

  return (
    <MsalProvider instance={msalInstance}>
      <AuthGate>{children}</AuthGate>
    </MsalProvider>
  );
}

export function useAppAuth() {
  return useContext(AuthContext);
}

function AuthGate({ children }) {
  const { accounts, inProgress, instance } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  const account = accounts[0] ?? null;
  const [accessClaims, setAccessClaims] = useState(null);
  const [isTokenLoading, setIsTokenLoading] = useState(true);
  const [tokenError, setTokenError] = useState('');

  const signIn = useCallback(() => {
    instance.loginRedirect(loginRequest);
  }, [instance]);

  const signOut = useCallback(() => {
    instance.logoutRedirect({ account });
  }, [account, instance]);

  const getAccessToken = useCallback(async () => {
    const activeAccount = account ?? instance.getAllAccounts()[0];
    if (!activeAccount) {
      throw new Error('User is not signed in.');
    }

    try {
      const tokenResult = await instance.acquireTokenSilent({
        ...loginRequest,
        account: activeAccount
      });

      return tokenResult.accessToken;
    } catch (err) {
      if (err instanceof InteractionRequiredAuthError) {
        await instance.acquireTokenRedirect({
          ...loginRequest,
          account: activeAccount
        });
      }

      throw err;
    }
  }, [account, instance]);

  useEffect(() => {
    if (!isAuthenticated || !account) {
      configureApiAuth(null);
      setAccessClaims(null);
      setIsTokenLoading(false);
      return undefined;
    }

    let isMounted = true;
    configureApiAuth(getAccessToken);
    setIsTokenLoading(true);

    getAccessToken()
      .then((token) => {
        if (isMounted) {
          setAccessClaims(decodeJwtPayload(token));
          setTokenError('');
        }
      })
      .catch((err) => {
        if (isMounted) {
          setTokenError(err.message || 'Unable to acquire API access token.');
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsTokenLoading(false);
        }
      });

    return () => {
      isMounted = false;
      configureApiAuth(null);
    };
  }, [account, getAccessToken, isAuthenticated]);

  if (inProgress !== InteractionStatus.None) {
    return <div className="route-loading">Completing sign-in...</div>;
  }

  if (!isAuthenticated) {
    return <SignInPage onSignIn={signIn} />;
  }

  if (isTokenLoading) {
    return <div className="route-loading">Checking dashboard access...</div>;
  }

  if (tokenError) {
    return <AuthStatePage title="API token could not be acquired" messages={[tokenError]} actionLabel="Sign in again" onAction={signIn} />;
  }

  const claimSources = [account?.idTokenClaims, accessClaims].filter(Boolean);
  const roles = collectRoleClaims(claimSources);
  const canAdmin = hasAnyRole(roles, roleConfig.admin);
  const canEdit = canAdmin || hasAnyRole(roles, roleConfig.editor);
  const canRead = canEdit || hasAnyRole(roles, roleConfig.reader);

  if (!canRead) {
    return (
      <AuthStatePage
        title="Access is not assigned"
        messages={[
          'Your sign-in succeeded, but your Entra token does not contain one of the configured DBA Capacity Reader, Editor, or Admin roles/groups.',
          `Accepted Reader roles/groups: ${roleConfig.reader.join(', ')}`,
          `Accepted Editor roles/groups: ${roleConfig.editor.join(', ')}`,
          `Accepted Admin roles/groups: ${roleConfig.admin.join(', ')}`
        ]}
        actionLabel="Sign out"
        onAction={signOut}
      />
    );
  }

  const value = {
    authEnabled: true,
    userName: account?.name || account?.username || 'Signed-in user',
    roles,
    canRead,
    canEdit,
    canAdmin,
    signIn,
    signOut,
    getAccessToken
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

function SignInPage({ onSignIn }) {
  return (
    <main className="auth-page">
      <section className="auth-panel">
        <ShieldCheck aria-hidden="true" size={28} />
        <div>
          <p className="eyebrow">DBA Capacity</p>
          <h1>Sign in required</h1>
          <p>Use your Microsoft Entra ID account to open the dashboard.</p>
        </div>
        <button type="button" className="secondary-action auth-primary-action" onClick={onSignIn}>
          Sign in
        </button>
      </section>
    </main>
  );
}

function AuthStatePage({ title, messages, actionLabel, onAction }) {
  return (
    <main className="auth-page">
      <section className="auth-panel auth-panel-wide">
        <ShieldCheck aria-hidden="true" size={28} />
        <div>
          <p className="eyebrow">DBA Capacity</p>
          <h1>{title}</h1>
          {messages.map((message) => (
            <p key={message}>{message}</p>
          ))}
        </div>
        {actionLabel && onAction ? (
          <button type="button" className="secondary-action auth-primary-action" onClick={onAction}>
            {actionLabel}
          </button>
        ) : null}
      </section>
    </main>
  );
}

function collectRoleClaims(claimSources) {
  const values = claimSources.flatMap((claims) => [
    ...normalizeClaimValue(claims?.roles),
    ...normalizeClaimValue(claims?.role),
    ...normalizeClaimValue(claims?.groups),
    ...normalizeClaimValue(claims?.wids)
  ]);
  const seen = new Set();

  return values.filter((value) => {
    const key = value.toLowerCase();
    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

function normalizeClaimValue(value) {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value.flatMap(normalizeClaimValue);
  }

  return String(value)
    .split(/[;,]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function hasAnyRole(userRoles, allowedRoles) {
  const assignedRoles = new Set(userRoles.map((role) => role.toLowerCase()));
  return allowedRoles.some((role) => assignedRoles.has(role.toLowerCase()));
}

function decodeJwtPayload(token) {
  const payload = token?.split('.')[1];
  if (!payload) {
    return null;
  }

  try {
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
    const json = decodeURIComponent(
      window
        .atob(padded)
        .split('')
        .map((char) => `%${char.charCodeAt(0).toString(16).padStart(2, '0')}`)
        .join('')
    );

    return JSON.parse(json);
  } catch {
    return null;
  }
}

const disabledAuthContext = {
  authEnabled: false,
  userName: 'Local user',
  roles: ['Local.Admin'],
  canRead: true,
  canEdit: true,
  canAdmin: true,
  signIn: () => {},
  signOut: () => {}
};
