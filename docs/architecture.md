# Architecture

## Overview

EphemGate is a dual-portal system for managing Microsoft Entra ID Temporary Access Passes (TAP). It follows a serverless architecture on Azure.

## High-Level Architecture

```
                    ┌─────────────────┐
                    │   End Users /   │
                    │   Helpdesk      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │    Browser      │
                    │   (MSAL.js)     │
                    └───┬─────────┬───┘
                        │         │
           ┌────────────▼──┐  ┌───▼────────────┐
           │  Self-Service │  │    Helpdesk     │
           │  Static Web   │  │  Static Web     │
           │  App (SWA)    │  │  App (SWA)      │
           └───────┬───────┘  └───────┬─────────┘
                   │                  │
           ┌───────▼───────┐  ┌───────▼─────────┐
           │  Self-Service │  │    Helpdesk      │
           │  Function App │  │  Function App    │
           │  (Easy Auth)  │  │  (Easy Auth)     │
           │  Delegated    │  │  App Permissions  │
           └───────┬───────┘  └───────┬─────────┘
                   │                  │
           ┌───────▼──────────────────▼─────────┐
           │         Microsoft Graph API         │
           │   (Authentication Methods API)      │
           └────────────────────────────────────┘

           ┌────────────────────────────────────┐
           │      Shared Infrastructure         │
           │  ┌──────────┐  ┌──────────────┐    │
           │  │ Storage  │  │ App Insights │    │
           │  │ Account  │  │ + Log        │    │
           │  │ (Tables) │  │ Analytics    │    │
           │  └──────────┘  └──────────────┘    │
           └────────────────────────────────────┘
```

## Component Details

### Static Web Apps (Frontend)
- Single-page applications (SPA) using vanilla HTML/CSS/JS
- MSAL.js v2 for authentication (via CDN)
- No build framework required
- Served via Azure Static Web Apps (Standard SKU)

### Function Apps (Backend)
- Azure Functions v4 programming model
- Node.js 24 LTS runtime
- Easy Auth for token validation
- System-assigned Managed Identity for Graph API access
- Application Insights for telemetry

### Storage Account
- Azure Table Storage for audit logs
- Separate tables: `TapAuditSelfService`, `TapAuditHelpdesk`
- `RateLimitTracking` table for helpdesk rate limiting
- Access via Managed Identity (Storage Table Data Contributor role)

### Monitoring
- Application Insights for request/dependency tracking
- Log Analytics Workspace for log aggregation
- Shared across both portals

## Authentication Flows

### Self-Service (Delegated)
1. MSAL.js acquires token with `UserAuthenticationMethod.ReadWrite` scope
2. Token sent as Bearer to Function App
3. Easy Auth validates the token
4. Function App uses the delegated token context to call Graph API

### Helpdesk (Application)
1. MSAL.js acquires token with basic scopes (`User.Read`, etc.)
2. Token sent as Bearer to Function App
3. Easy Auth validates the token
4. Function App checks JWT `roles` claim for App Role
5. Function App uses system-assigned Managed Identity to call Graph API
6. Graph API permissions granted directly to the Managed Identity SP

## Security Layers

1. **MSAL.js** – Client-side authentication
2. **Easy Auth** – Server-side token validation
3. **App Roles** – Authorization (Helpdesk only)
4. **Privileged User Guard** – Prevents TAP for admin accounts
5. **Rate Limiting** – Prevents abuse
6. **Audit Logging** – Full activity trail
7. **Email Notification** – User awareness
