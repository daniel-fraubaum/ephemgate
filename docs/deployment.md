# Deployment Guide

## Prerequisites

### Required Tools
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) v2.60+
- [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) v4
- [Azure Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/) (`npm i -g @azure/static-web-apps-cli`)
- [Node.js](https://nodejs.org/) v24 LTS
- [jq](https://jqlang.github.io/jq/) (Bash script only)

### Required Azure Permissions
- **Subscription**: Contributor + User Access Administrator (or Owner)
- **Entra ID**: Application Administrator or Cloud Application Administrator
- **Graph API**: Global Admin or Privileged Role Admin (for admin consent)

## Quick Start

### macOS / Linux

```bash
# Login to Azure
az login

# Run the deploy script
chmod +x infra/deploy.sh
./infra/deploy.sh --project ephemgate-prod
```

### Windows (PowerShell)

```powershell
# Login to Azure
az login

# Run the deploy script
.\infra\deploy.ps1 -Project ephemgate-prod
```

## Deploy Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--project` / `-Project` | Yes | — | Project name (used for resource naming) |
| `--location` / `-Location` | No | `germanywestcentral` | Azure region |
| `--app` / `-App` | No | both | Deploy only `selfservice` or `helpdesk` |
| `--secret-ss` / `-SecretSS` | No | — | Existing Self-Service client secret |
| `--secret-hd` / `-SecretHD` | No | — | Existing Helpdesk client secret |
| `--skip-infra` / `-SkipInfra` | No | — | Skip Bicep deployment |
| `--skip-backend` / `-SkipBackend` | No | — | Skip backend deployment |
| `--skip-frontend` / `-SkipFrontend` | No | — | Skip frontend deployment |
| `--domain-ss` / `-DomainSS` | No | — | Custom domain for Self-Service |
| `--domain-hd` / `-DomainHD` | No | — | Custom domain for Helpdesk |

## Deployment Steps (what the script does)

1. **Login Check** – Verifies `az login` is active
2. **Resource Group** – Prompts for RG name (default: `rg-<project>`)
3. **App Registrations** – Creates 2 Entra ID App Registrations
4. **Bicep Deployment** – Deploys all Azure infrastructure
5. **Graph Permissions** – Assigns Graph API permissions to Managed Identities
6. **Backend Deploy** – `npm ci` + `func azure functionapp publish` for both backends
7. **Frontend Config** – Generates `authConfig.js` from Bicep outputs
8. **Frontend Deploy** – `swa deploy` for both Static Web Apps
9. **Redirect URIs** – Registers SWA URLs as redirect URIs on App Registrations
10. **Admin Consent** – Grants admin consent for API permissions

## Re-deployment

To re-deploy without creating new App Registrations:

```bash
# Skip infra, only update code
./infra/deploy.sh --project ephemgate-prod \
  --secret-ss "existing-secret" \
  --secret-hd "existing-secret" \
  --skip-infra

# Only update Self-Service backend
./infra/deploy.sh --project ephemgate-prod \
  --app selfservice \
  --skip-infra \
  --skip-frontend
```

## Post-Deployment Configuration

### 1. Enable Assignment Required
For both App Registrations, enable "Assignment required" on the Enterprise Application:

```bash
# Get Service Principal Object IDs
SS_SP_ID=$(az ad sp list --display-name "ephemgate-prod-selfservice" --query "[0].id" -o tsv)
HD_SP_ID=$(az ad sp list --display-name "ephemgate-prod-helpdesk" --query "[0].id" -o tsv)

# Enable assignment required
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SS_SP_ID" \
  --body '{"appRoleAssignmentRequired": true}'

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$HD_SP_ID" \
  --body '{"appRoleAssignmentRequired": true}'
```

### 2. Assign Users/Groups
Assign users or groups to each Enterprise Application in the Azure Portal or via CLI.

### 3. Assign Helpdesk App Roles
Assign the `Helpdesk.TapAdmin` or `Helpdesk.TapViewer` roles to helpdesk agents.

### 4. Configure Conditional Access
See [conditional-access.md](conditional-access.md) for recommended policies.

### 5. Configure Helpdesk Settings
Set optional app settings on the Helpdesk Function App:
- `BLOCKED_GROUP_IDS` – Comma-separated Entra Group IDs to block
- `NOTIFICATION_SENDER` – Shared mailbox address for email notifications

## Troubleshooting

### "Not logged in" error
Run `az login` and ensure the correct subscription is selected:
```bash
az account set --subscription "<subscription-id>"
```

### Graph API permission errors
Ensure you have Global Admin or Privileged Role Admin to grant admin consent.

### Function App 401 errors
Check that Easy Auth is properly configured on the Function App in the Azure Portal under Authentication.

### SWA deployment fails
Ensure the SWA CLI is installed: `npm i -g @azure/static-web-apps-cli`
