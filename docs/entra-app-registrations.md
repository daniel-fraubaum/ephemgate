# Entra ID App Registrations

EphemGate requires **two** App Registrations in Microsoft Entra ID.

## App Registration 1: Self-Service Portal

### Purpose
Allows end users to create their own Temporary Access Pass. No client secret needed – uses PKCE flow for the SPA and JWKS for backend token validation.

### Create via Azure CLI

```bash
# Create the App Registration (no secret needed)
SS_APP_ID=$(az ad app create \
  --display-name "EphemGate Self-Service" \
  --sign-in-audience "AzureADMyOrg" \
  --query "appId" -o tsv)

# Expose an API scope
az ad app update --id "$SS_APP_ID" \
  --identifier-uris "api://$SS_APP_ID"

# Add the Access scope (via Graph API)
SS_OBJECT_ID=$(az ad app show --id "$SS_APP_ID" --query "id" -o tsv)
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$SS_OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body '{"api":{"oauth2PermissionScopes":[{"id":"'$(uuidgen)'","adminConsentDescription":"Access EphemGate Self-Service API","adminConsentDisplayName":"Access","isEnabled":true,"type":"User","userConsentDescription":"Access EphemGate Self-Service API","userConsentDisplayName":"Access","value":"Access"}]}}'
```

### Configuration
- **Platform**: Single-page application (SPA)
- **Redirect URI**: Set by deploy script to the Static Web App URL
- **Supported account types**: Single tenant (this org only)
- **No Client Secret** – PKCE flow for SPA, JWKS for backend validation
- **Expose an API**: `api://<client-id>/Access`

---

## App Registration 2: Helpdesk Portal

### Purpose
Allows authorized helpdesk agents to create TAPs for end users. No client secret needed – uses PKCE flow for the SPA and JWKS for backend token validation. Graph API access is via Managed Identity.

### Create via Azure CLI

```bash
# Create the App Registration with App Roles (no secret needed)
HD_APP_ID=$(az ad app create \
  --display-name "EphemGate Helpdesk" \
  --sign-in-audience "AzureADMyOrg" \
  --app-roles '[
    {
      "allowedMemberTypes": ["User"],
      "description": "Can create TAPs for users and view audit logs",
      "displayName": "Helpdesk TAP Admin",
      "isEnabled": true,
      "value": "Helpdesk.TapAdmin"
    },
    {
      "allowedMemberTypes": ["User"],
      "description": "Can view TAP audit logs",
      "displayName": "Helpdesk TAP Viewer",
      "isEnabled": true,
      "value": "Helpdesk.TapViewer"
    }
  ]' \
  --query "appId" -o tsv)

# Expose an API scope
az ad app update --id "$HD_APP_ID" \
  --identifier-uris "api://$HD_APP_ID"

# Add the Access scope (via Graph API)
HD_OBJECT_ID=$(az ad app show --id "$HD_APP_ID" --query "id" -o tsv)
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$HD_OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body '{"api":{"oauth2PermissionScopes":[{"id":"'$(uuidgen)'","adminConsentDescription":"Access EphemGate Helpdesk API","adminConsentDisplayName":"Access","isEnabled":true,"type":"User","userConsentDescription":"Access EphemGate Helpdesk API","userConsentDisplayName":"Access","value":"Access"}]}}'
```

### Configuration
- **Platform**: Single-page application (SPA)
- **Redirect URI**: Set by deploy script to the Static Web App URL
- **Supported account types**: Single tenant (this org only)
- **No Client Secret** – PKCE flow for SPA, JWKS for backend validation
- **Expose an API**: `api://<client-id>/Access`

### Application Permissions (Managed Identity)

These permissions are granted to the **Function App's Managed Identity**, not to the App Registration.

| Permission | Type | ID | Description |
|------------|------|-----|-------------|
| `UserAuthenticationMethod.ReadWrite.All` | Application | `50483e42-d915-4231-9639-7fdb7fd190e5` | Read/write all users' auth methods |
| `User.Read.All` | Application | `df021288-bdef-4463-88db-98f22de89214` | Read all users' profiles |
| `Directory.Read.All` | Application | `7ab1d382-f21e-4acd-a863-ba3e13f7da61` | Read directory data |
| `RoleManagement.Read.Directory` | Application | `483bed4a-2ad3-4361-a73b-c83ccdbdc53c` | Read role assignments |
| `Mail.Send` | Application | `b633e1c5-b582-4048-a93e-9f11b44c7e96` | Send mail as any user |

### Assign Graph permissions to Managed Identity

```bash
GRAPH_SP_ID=$(az ad sp show --id "00000003-0000-0000-c000-000000000000" --query "id" -o tsv)
FUNC_PRINCIPAL_ID="<function-app-managed-identity-principal-id>"

# Assign each role
for ROLE_ID in \
  "50483e42-d915-4231-9639-7fdb7fd190e5" \
  "df021288-bdef-4463-88db-98f22de89214" \
  "7ab1d382-f21e-4acd-a863-ba3e13f7da61" \
  "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" \
  "b633e1c5-b582-4048-a93e-9f11b44c7e96"; do

  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${GRAPH_SP_ID}/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\": \"${FUNC_PRINCIPAL_ID}\", \"resourceId\": \"${GRAPH_SP_ID}\", \"appRoleId\": \"${ROLE_ID}\"}"
done
```

### App Roles

| Role | Value | Description |
|------|-------|-------------|
| Helpdesk TAP Admin | `Helpdesk.TapAdmin` | Can search users, create TAPs, and view audit logs |
| Helpdesk TAP Viewer | `Helpdesk.TapViewer` | Can only view audit logs |

### Assign App Roles to Users

```bash
# Get the Enterprise Application (Service Principal) Object ID
HD_SP_ID=$(az ad sp list --display-name "EphemGate Helpdesk" --query "[0].id" -o tsv)
HD_APP_ROLE_ID=$(az ad sp show --id "$HD_SP_ID" --query "appRoles[?value=='Helpdesk.TapAdmin'].id" -o tsv)
USER_ID="<user-object-id>"

# Assign the role
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${HD_SP_ID}/appRoleAssignedTo" \
  --headers "Content-Type=application/json" \
  --body "{\"principalId\": \"${USER_ID}\", \"resourceId\": \"${HD_SP_ID}\", \"appRoleId\": \"${HD_APP_ROLE_ID}\"}"
```

### Configuration
- **Platform**: Single-page application (SPA)
- **Redirect URI**: Set by deploy script to the Static Web App URL
- **Supported account types**: Single tenant (this org only)
- **ID Tokens**: Enabled (for App Role claims in the JWT)
- **Access Tokens**: Disabled
- **No Client Secret** – PKCE flow for SPA, JWKS for backend validation
