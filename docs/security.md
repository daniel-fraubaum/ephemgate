# Security

## Overview

EphemGate implements multiple security layers to protect against misuse of Temporary Access Pass capabilities. This document explains the security architecture and the reasoning behind each control.

## Why Application Permissions Are Dangerous

The Helpdesk portal uses **application permissions** (`UserAuthenticationMethod.ReadWrite.All`) via Managed Identity. This means the backend can create TAPs for **any user in the directory**, including:

- Global Administrators
- Privileged Role Administrators
- Security Administrators
- Other highly privileged accounts

If a TAP is created for a privileged account, an attacker could use it to sign in as that account, bypass MFA, and escalate privileges.

**This is why the Privileged User Guard is critical.**

## Privileged User Guard

The Privileged User Guard (`helpdesk/backend/src/lib/privilegedUserGuard.js`) is the most important security control in the Helpdesk portal.

### What It Does

Before every TAP creation request, the guard checks the **target user** (the user who would receive the TAP):

#### Check 1: Directory Role Assignments
Queries Microsoft Graph for the target user's directory role assignments. If the user has any of the following roles, the request is **blocked**:

| Role | ID | Why Blocked |
|------|-----|------------|
| Global Administrator | `62e90394-...` | Full tenant control |
| Privileged Role Administrator | `e8611ab8-...` | Can assign admin roles |
| Privileged Authentication Administrator | `7be44c8a-...` | Can manage auth for admins |
| Security Administrator | `194ae4cb-...` | Security policy control |
| Application Administrator | `9b895d92-...` | Can manage app registrations |
| Exchange Administrator | `29232cdf-...` | Mailbox/transport access |
| SharePoint Administrator | `f28a1f50-...` | SharePoint tenant control |
| Conditional Access Administrator | `b1be1c3e-...` | Can modify CA policies |

#### Check 2: Blocked Group Membership
Checks if the target user is a member of any group listed in the `BLOCKED_GROUP_IDS` environment variable. This allows administrators to protect additional accounts:

- Breakglass/emergency access accounts
- PAW (Privileged Access Workstation) users
- Any other sensitive accounts

### What Happens on Block

1. **HTTP 403** returned to the helpdesk agent
2. **Audit log entry** with action `BLOCKED_PRIVILEGED` and the specific reason
3. **CRITICAL severity log** in Application Insights

### Configuration

Set the `BLOCKED_GROUP_IDS` app setting on the Helpdesk Function App:

```
BLOCKED_GROUP_IDS=<group-id-1>,<group-id-2>,<group-id-3>
```

## App Role Authorization

The Helpdesk portal enforces authorization via Entra ID App Roles:

- **`Helpdesk.TapAdmin`** – Required for searching users and creating TAPs
- **`Helpdesk.TapViewer`** – Required for viewing audit logs (TapAdmin also has this access)

### How It Works

1. User signs in via MSAL.js
2. Frontend acquires a token with `api://<backend-client-id>/Access` scope
3. Frontend sends the token as `Authorization: Bearer <token>` header
4. Backend validates the JWT signature via Microsoft JWKS endpoint (public signing keys)
5. Backend extracts the `roles` claim from the validated JWT payload
6. Checks if the user has the required role for the endpoint
7. Returns HTTP 403 if the role is missing

This approach is more secure than Easy Auth because:
- **No client secret stored** – The JWKS endpoint provides public keys for signature verification
- **No secret rotation** – Microsoft rotates their signing keys automatically
- **No expiring credentials** – Nothing to monitor or renew
- **Full control** – Validation logic is in code, auditable and testable

### Why Not Just Use Entra Groups?

App Roles provide several advantages:
- Included in the JWT token claims (no additional Graph API call needed)
- Enforced at the application level (not just group membership)
- Visible in the Enterprise Application assignment blade
- Can be audited via Entra ID sign-in logs

## Rate Limiting

The Helpdesk portal implements rate limiting to prevent abuse:

- **Per Agent**: Maximum 10 TAP requests per hour
- **Per Target User**: Maximum 1 active TAP per user

### Why Rate Limiting?

Even authorized helpdesk agents could be compromised or could misuse their access. Rate limiting:
- Limits the blast radius of a compromised agent account
- Prevents bulk TAP creation for social engineering attacks
- Creates a speed bump that makes abuse more detectable

### Implementation

Rate limit tracking uses Azure Table Storage (`RateLimitTracking` table):
- Partition key: `agent-{agentId}` or `target-{targetUserId}`
- Timestamp-based filtering for the 1-hour window
- Expiration tracking for active TAPs

## Audit Logging

Every TAP request is logged to Azure Table Storage with:
- Who requested it (agent UPN/OID)
- Who it was for (target UPN/OID)
- What happened (SUCCESS, DENIED, BLOCKED_PRIVILEGED, RATE_LIMITED, ERROR)
- Why it was denied (denial reason)
- Request metadata (IP, user agent)

### Audit Log Retention

Table Storage does not have automatic TTL. Consider implementing a cleanup function or Azure Data Lifecycle Management policy.

## Email Notification

When a TAP is created in the Helpdesk portal, the target user receives an email notification:
- Informs them that a TAP was created for their account
- Includes the agent's UPN and timestamp
- Instructs them to contact IT Support if they didn't request it

This creates an independent notification channel that can detect unauthorized TAP creation.

### Configuration

Set `NOTIFICATION_SENDER` on the Helpdesk Function App to a shared mailbox address:
```
NOTIFICATION_SENDER=noreply@contoso.com
```

The Managed Identity needs the `Mail.Send` permission to send emails from this mailbox.

## Network Security

### Conditional Access
See [conditional-access.md](conditional-access.md) for recommended policies:
- **Self-Service**: MFA + Compliant Device
- **Helpdesk**: MFA + Compliant Device + Corporate Network

### Static Web App Headers
Both frontends set security headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy` (restricts script sources to self + MSAL CDN)

### Function App Security
- HTTPS only
- TLS 1.2 minimum
- FTPS disabled
- Code-based JWT validation via JWKS (no Easy Auth)
- Managed Identity for Graph API (no stored secrets)

## Recommendations

1. **Enable Assignment Required** on both Enterprise Applications
2. **Regular Audit Reviews** – Review the audit log regularly for anomalies
3. **Alert on BLOCKED_PRIVILEGED** – Set up Application Insights alerts for critical log entries
4. **Separate PAW accounts** – Add PAW user groups to `BLOCKED_GROUP_IDS`
5. **Monitor Sign-in Logs** – Watch for unusual sign-in patterns on the Helpdesk portal
6. **Conditional Access** – Always require MFA and compliant devices
7. **Least Privilege** – Only assign `Helpdesk.TapAdmin` to agents who need it
