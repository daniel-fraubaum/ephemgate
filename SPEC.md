# EphemGate – Technical Specification

## Overview

EphemGate is a Temporary Access Pass (TAP) Self-Service & Helpdesk Portal for Microsoft Entra ID. It consists of two separate web applications deployed from a single monorepo.

## System Components

### 1. Self-Service Portal

**Purpose:** End users create their own Temporary Access Pass using delegated permissions.

**Auth Flow:**
1. User authenticates via MSAL.js with scopes: `api://<backend-client-id>/Access`
2. Frontend sends requests to Function App backend with Bearer token
3. Backend validates the JWT via JWKS endpoint (Microsoft public signing keys) – no client secret needed
4. Backend uses Managed Identity to call Graph API to create a TAP for the authenticated user

**Endpoints:**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/my-auth-methods` | JWT (JWKS) | Lists the user's own authentication methods |
| `PUT` | `/api/generate-tap` | JWT (JWKS) | Creates a TAP for the signed-in user |
| `GET` | `/api/health` | Anonymous | Health check endpoint |

### 2. Helpdesk Portal

**Purpose:** Authorized helpdesk agents create TAPs for end users using application permissions via Managed Identity.

**Auth Flow:**
1. Agent authenticates via MSAL.js with scopes: `api://<backend-client-id>/Access`
2. Backend validates JWT via JWKS endpoint and checks for App Role `Helpdesk.TapAdmin` in JWT `roles` claim
3. Agent searches for target user via Graph API
4. **Privileged User Guard** validates the target user is not a privileged account
5. **Rate Limiter** checks per-agent and per-user limits
6. Backend uses system-assigned Managed Identity to call Graph API with application permissions
7. Graph API creates a TAP for the target user
8. Optional email notification sent to the target user via Graph API

**Endpoints:**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/search-user?q={query}` | JWT (JWKS) + `Helpdesk.TapAdmin` | Search users by UPN or display name |
| `PUT` | `/api/generate-tap/{userId}` | JWT (JWKS) + `Helpdesk.TapAdmin` | Create TAP for specified user |
| `GET` | `/api/audit-log?days={n}` | JWT (JWKS) + `Helpdesk.TapAdmin` or `Helpdesk.TapViewer` | Query audit log entries |
| `GET` | `/api/health` | Anonymous | Health check endpoint |

**App Roles:**
- `Helpdesk.TapAdmin` – Can search users, create TAPs, and view audit logs
- `Helpdesk.TapViewer` – Can only view audit logs

## Entra ID App Registrations

### App Registration 1: Self-Service Portal
- **Type:** Single-page application (SPA)
- **No Client Secret** – uses PKCE flow
- **Expose an API:** `api://<client-id>/Access` scope
- **Redirect URI:** `https://<swa-hostname>` (set by deploy script)
- **JWT Validation:** Code-based via JWKS endpoint (no Easy Auth)
- **Managed Identity:** System-assigned on the Function App (for Graph API + Table Storage)

### App Registration 2: Helpdesk Portal
- **Type:** Single-page application (SPA)
- **No Client Secret** – uses PKCE flow
- **Expose an API:** `api://<client-id>/Access` scope
- **Application Permissions (granted to Managed Identity):**
  - `UserAuthenticationMethod.ReadWrite.All`
  - `User.Read.All`
  - `Directory.Read.All`
  - `RoleManagement.Read.Directory`
  - `Mail.Send`
- **App Roles:**
  - `Helpdesk.TapAdmin` (value: `Helpdesk.TapAdmin`)
  - `Helpdesk.TapViewer` (value: `Helpdesk.TapViewer`)
- **Redirect URI:** `https://<swa-hostname>` (set by deploy script)
- **JWT Validation:** Code-based via JWKS endpoint (no Easy Auth)

## Authentication & Authorization

EphemGate follows a **Zero Secrets** architecture:
- **JWT Validation:** Code-based using `jose` library against Microsoft JWKS endpoint (`login.microsoftonline.com/.../discovery/v2.0/keys`). No client secret required.
- **Graph API:** Managed Identity (system-assigned) for both Function Apps. No stored credentials.
- **SPA Login:** MSAL.js with Authorization Code Flow + PKCE. No client secret for SPA apps.
- **Result:** Zero stored secrets, zero secret rotation, zero expiring credentials.

## TAP Configuration

### Self-Service Defaults
| Setting | Default | Description |
|---------|---------|-------------|
| `TAP_LIFETIME_MINUTES` | 60 | TAP validity duration |
| `TAP_IS_USABLE_ONCE` | true | Single-use TAP |
| `TAP_DISPLAY_TIMEOUT_SECONDS` | 300 | Frontend display timeout (5 min) |

### Helpdesk Defaults
| Setting | Default | Description |
|---------|---------|-------------|
| `TAP_LIFETIME_MINUTES` | 120 | TAP validity duration |
| `TAP_IS_USABLE_ONCE` | true | Single-use TAP |
| `TAP_DISPLAY_TIMEOUT_SECONDS` | 120 | Frontend display timeout (2 min) |
| `BLOCKED_GROUP_IDS` | — | Comma-separated Entra Group IDs |
| `NOTIFICATION_SENDER` | — | Email sender address (shared mailbox) |

## Security

### Privileged User Guard
Before issuing a TAP in the Helpdesk portal, the target user is checked:

1. **Directory Role Check:** Is the user assigned any of these built-in Entra roles?
   - Global Administrator (`62e90394-69f5-4237-9190-012177145e10`)
   - Privileged Role Administrator (`e8611ab8-c189-46e8-94e1-60213ab1f814`)
   - Privileged Authentication Administrator (`7be44c8a-adaf-4e2a-84d6-ab2649e08a13`)
   - Security Administrator (`194ae4cb-b126-40b2-bd5b-6091b380977d`)
   - Application Administrator (`9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3`)
   - Exchange Administrator (`29232cdf-9323-42fd-ade2-1d097af3e4de`)
   - SharePoint Administrator (`f28a1f50-f6e7-4571-818b-6a12f2af6b6c`)
   - Conditional Access Administrator (`b1be1c3e-b65d-4f19-8427-f6fa0d97feb9`)

2. **Blocked Group Check:** Is the user a member of any group listed in `BLOCKED_GROUP_IDS`?

If either check fails → HTTP 403 + audit log entry with action `BLOCKED_PRIVILEGED`.

### Rate Limiting (Helpdesk only)
- Max 10 TAP requests per agent per hour
- Max 1 active TAP per target user
- Tracked via Azure Table Storage (`RateLimitTracking` table)
- Exceeded → HTTP 429

## Audit Log Schema

Stored in Azure Table Storage (`TapAuditSelfService` / `TapAuditHelpdesk`).

| Field | Type | Description |
|-------|------|-------------|
| `PartitionKey` | String | `YYYY-MM-DD` (UTC) |
| `RowKey` | String | UUID v4 |
| `Timestamp` | DateTime | Auto-set by Table Storage |
| `Portal` | String | `selfservice` or `helpdesk` |
| `AgentUPN` | String | Agent UPN (helpdesk only) |
| `AgentId` | String | Agent OID (helpdesk only) |
| `TargetUPN` | String | Target user UPN |
| `TargetId` | String | Target user OID |
| `Action` | String | `SUCCESS`, `DENIED`, `BLOCKED_PRIVILEGED`, `RATE_LIMITED`, `ERROR` |
| `DenialReason` | String | Reason for non-success |
| `TapLifetimeMinutes` | Int32 | Configured lifetime |
| `TapIsUsableOnce` | Boolean | One-time use flag |
| `ClientIp` | String | Source IP address |
| `UserAgent` | String | Browser user agent |

## Azure Resources

All deployed into a single resource group `rg-<project>`:

| Resource | Name Pattern | SKU/Tier |
|----------|-------------|----------|
| Resource Group | `rg-<project>` | — |
| Log Analytics Workspace | `<project>-law` | PerGB2018 |
| Application Insights | `<project>-ai` | — |
| Storage Account | `<project>st<uniqueString>` | Standard_LRS |
| App Service Plan | `<project>-plan` | Linux B1 |
| Function App (Self-Service) | `<project>-ss-func` | — |
| Static Web App (Self-Service) | `<project>-ss-swa` | Standard |
| Function App (Helpdesk) | `<project>-hd-func` | — |
| Static Web App (Helpdesk) | `<project>-hd-swa` | Standard |

## Technology Stack

- **Runtime:** Node.js 24 LTS
- **Backend Framework:** Azure Functions v4 (`@azure/functions`)
- **Frontend:** Vanilla HTML/CSS/JS (single-file SPA)
- **Auth Library:** MSAL.js v2 (via CDN)
- **Graph SDK:** `@microsoft/microsoft-graph-client` + `@azure/identity`
- **Infrastructure:** Azure Bicep (subscription scope)
- **Monitoring:** Application Insights + Log Analytics
- **Storage:** Azure Table Storage (`@azure/data-tables`)
- **Linting:** ESLint 9 (flat config)
