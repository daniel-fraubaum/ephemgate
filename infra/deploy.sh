#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# EphemGate – Automated Deployment Script (Bash)
# Deploys infrastructure, backend, and frontend for Self-Service & Helpdesk portals
###############################################################################

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step_num=0
step() {
  step_num=$((step_num + 1))
  echo ""
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}${BOLD}  Step ${step_num}: $1${NC}"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
}

info()    { echo -e "${CYAN}ℹ  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ── Default Values ──────────────────────────────────────────────────────────
PROJECT=""
LOCATION="germanywestcentral"
APP=""
SKIP_INFRA=false
SKIP_BACKEND=false
SKIP_FRONTEND=false
DOMAIN_SS=""
DOMAIN_HD=""
RESOURCE_GROUP=""

# ── Parse Arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="$2"; shift 2;;
    --location)    LOCATION="$2"; shift 2;;
    --app)         APP="$2"; shift 2;;
    --skip-infra)  SKIP_INFRA=true; shift;;
    --skip-backend)  SKIP_BACKEND=true; shift;;
    --skip-frontend) SKIP_FRONTEND=true; shift;;
    --domain-ss)   DOMAIN_SS="$2"; shift 2;;
    --domain-hd)   DOMAIN_HD="$2"; shift 2;;
    *) error "Unknown argument: $1";;
  esac
done

[[ -z "$PROJECT" ]] && error "Missing required parameter: --project <name>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEPLOY_SS=true
DEPLOY_HD=true
if [[ -n "$APP" ]]; then
  [[ "$APP" == "selfservice" ]] && DEPLOY_HD=false
  [[ "$APP" == "helpdesk" ]]    && DEPLOY_SS=false
fi

# ── Confirmation ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          EphemGate – Deployment Configuration              ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC} Project:          ${CYAN}${PROJECT}${NC}"
echo -e "${BOLD}║${NC} Location:         ${CYAN}${LOCATION}${NC}"
echo -e "${BOLD}║${NC} Deploy:           ${CYAN}$([ "$DEPLOY_SS" = true ] && echo "Self-Service")$([ "$DEPLOY_SS" = true ] && [ "$DEPLOY_HD" = true ] && echo " + ")$([ "$DEPLOY_HD" = true ] && echo "Helpdesk")${NC}"
echo -e "${BOLD}║${NC} Skip Infra:       ${CYAN}${SKIP_INFRA}${NC}"
echo -e "${BOLD}║${NC} Skip Backend:     ${CYAN}${SKIP_BACKEND}${NC}"
echo -e "${BOLD}║${NC} Skip Frontend:    ${CYAN}${SKIP_FRONTEND}${NC}"
[[ -n "$DOMAIN_SS" ]] && echo -e "${BOLD}║${NC} Custom Domain SS: ${CYAN}${DOMAIN_SS}${NC}"
[[ -n "$DOMAIN_HD" ]] && echo -e "${BOLD}║${NC} Custom Domain HD: ${CYAN}${DOMAIN_HD}${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "Proceed with deployment? (y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

# ── Step 1: Login Check ────────────────────────────────────────────────────
step "Checking Azure CLI login"
ACCOUNT=$(az account show --query '{name:name, id:id, tenantId:tenantId}' -o json 2>/dev/null) || error "Not logged in. Run: az login"
TENANT_ID=$(echo "$ACCOUNT" | jq -r '.tenantId')
SUB_NAME=$(echo "$ACCOUNT" | jq -r '.name')
SUB_ID=$(echo "$ACCOUNT" | jq -r '.id')
success "Logged in to subscription: ${SUB_NAME} (${SUB_ID})"
info "Tenant ID: ${TENANT_ID}"

# ── Step 2: Resource Group ─────────────────────────────────────────────────
step "Resource Group"
DEFAULT_RG="rg-${PROJECT}"
read -rp "Resource Group name (default: ${DEFAULT_RG}): " input_rg
RESOURCE_GROUP="${input_rg:-$DEFAULT_RG}"
info "Using resource group: ${RESOURCE_GROUP}"

# ── Step 3: App Registrations ──────────────────────────────────────────────
step "Entra ID App Registrations"

create_app_registration() {
  local display_name="$1"
  local type="$2"

  info "Creating/updating App Registration: ${display_name}"

  local existing_app_id
  existing_app_id=$(az ad app list --display-name "$display_name" --query "[0].appId" -o tsv 2>/dev/null || echo "")

  if [[ -n "$existing_app_id" && "$existing_app_id" != "None" ]]; then
    info "App Registration already exists: ${existing_app_id}"
    echo "$existing_app_id"
    return
  fi

  local app_id
  if [[ "$type" == "selfservice" ]]; then
    app_id=$(az ad app create \
      --display-name "$display_name" \
      --sign-in-audience "AzureADMyOrg" \
      --enable-id-token-issuance false \
      --enable-access-token-issuance false \
      --required-resource-accesses '[{
        "resourceAppId": "00000003-0000-0000-c000-000000000000",
        "resourceAccess": [
          {"id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d", "type": "Scope"},
          {"id": "b7887744-6746-4312-813d-72daeaee7e2d", "type": "Scope"}
        ]
      }]' \
      --query "appId" -o tsv)
  else
    # Helpdesk: delegated + app roles
    app_id=$(az ad app create \
      --display-name "$display_name" \
      --sign-in-audience "AzureADMyOrg" \
      --enable-id-token-issuance true \
      --enable-access-token-issuance false \
      --required-resource-accesses '[{
        "resourceAppId": "00000003-0000-0000-c000-000000000000",
        "resourceAccess": [
          {"id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d", "type": "Scope"},
          {"id": "37f7f235-527c-4136-accd-4a02d197296e", "type": "Scope"},
          {"id": "14dad69e-099b-42c9-810b-d002981feec1", "type": "Scope"},
          {"id": "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0", "type": "Scope"}
        ]
      }]' \
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
  fi

  success "Created App Registration: ${app_id}"
  echo "$app_id"
}

if [[ "$DEPLOY_SS" == true ]]; then
  SS_APP_NAME="${PROJECT}-selfservice"
  CLIENT_ID_SS=$(create_app_registration "$SS_APP_NAME" "selfservice")
fi

if [[ "$DEPLOY_HD" == true ]]; then
  HD_APP_NAME="${PROJECT}-helpdesk"
  CLIENT_ID_HD=$(create_app_registration "$HD_APP_NAME" "helpdesk")
fi

# ── Step 4: Bicep Deployment ───────────────────────────────────────────────
if [[ "$SKIP_INFRA" == false ]]; then
  step "Bicep Infrastructure Deployment"

  BICEP_PARAMS="projectName=${PROJECT} location=${LOCATION} entraTenantId=${TENANT_ID} resourceGroupName=${RESOURCE_GROUP}"
  [[ -n "${CLIENT_ID_SS:-}" ]] && BICEP_PARAMS+=" entraClientIdSS=${CLIENT_ID_SS}"
  [[ -n "${CLIENT_ID_HD:-}" ]] && BICEP_PARAMS+=" entraClientIdHD=${CLIENT_ID_HD}"
  [[ -n "$DOMAIN_SS" ]] && BICEP_PARAMS+=" customDomainSS=${DOMAIN_SS}"
  [[ -n "$DOMAIN_HD" ]] && BICEP_PARAMS+=" customDomainHD=${DOMAIN_HD}"

  DEPLOYMENT_OUTPUT=$(az deployment sub create \
    --name "ephemgate-$(date +%Y%m%d%H%M%S)" \
    --location "$LOCATION" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters $BICEP_PARAMS \
    --query "properties.outputs" -o json)

  FUNC_SS_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcSelfServiceName.value // empty')
  FUNC_SS_HOST=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcSelfServiceHostname.value // empty')
  FUNC_SS_PRINCIPAL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcSelfServicePrincipalId.value // empty')
  FUNC_HD_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcHelpdeskName.value // empty')
  FUNC_HD_HOST=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcHelpdeskHostname.value // empty')
  FUNC_HD_PRINCIPAL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.funcHelpdeskPrincipalId.value // empty')
  SWA_SS_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaSelfServiceName.value // empty')
  SWA_SS_HOST=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaSelfServiceHostname.value // empty')
  SWA_SS_TOKEN=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaSelfServiceDeploymentToken.value // empty')
  SWA_HD_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaHelpdeskName.value // empty')
  SWA_HD_HOST=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaHelpdeskHostname.value // empty')
  SWA_HD_TOKEN=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.swaHelpdeskDeploymentToken.value // empty')

  success "Infrastructure deployed successfully"
else
  step "Skipping infrastructure deployment"
  warn "Using existing resources. Retrieving outputs..."

  FUNC_SS_NAME="${PROJECT}-ss-func"
  FUNC_HD_NAME="${PROJECT}-hd-func"
  SWA_SS_NAME="${PROJECT}-ss-swa"
  SWA_HD_NAME="${PROJECT}-hd-swa"

  FUNC_SS_HOST=$(az functionapp show -n "$FUNC_SS_NAME" -g "$RESOURCE_GROUP" --query "defaultHostName" -o tsv 2>/dev/null || echo "")
  FUNC_HD_HOST=$(az functionapp show -n "$FUNC_HD_NAME" -g "$RESOURCE_GROUP" --query "defaultHostName" -o tsv 2>/dev/null || echo "")
  SWA_SS_HOST=$(az staticwebapp show -n "$SWA_SS_NAME" -g "$RESOURCE_GROUP" --query "defaultHostname" -o tsv 2>/dev/null || echo "")
  SWA_HD_HOST=$(az staticwebapp show -n "$SWA_HD_NAME" -g "$RESOURCE_GROUP" --query "defaultHostname" -o tsv 2>/dev/null || echo "")
  SWA_SS_TOKEN=$(az staticwebapp secrets list -n "$SWA_SS_NAME" -g "$RESOURCE_GROUP" --query "properties.apiKey" -o tsv 2>/dev/null || echo "")
  SWA_HD_TOKEN=$(az staticwebapp secrets list -n "$SWA_HD_NAME" -g "$RESOURCE_GROUP" --query "properties.apiKey" -o tsv 2>/dev/null || echo "")
  FUNC_SS_PRINCIPAL=$(az functionapp identity show -n "$FUNC_SS_NAME" -g "$RESOURCE_GROUP" --query "principalId" -o tsv 2>/dev/null || echo "")
  FUNC_HD_PRINCIPAL=$(az functionapp identity show -n "$FUNC_HD_NAME" -g "$RESOURCE_GROUP" --query "principalId" -o tsv 2>/dev/null || echo "")
fi

# ── Step 5: Graph API Permissions for Managed Identities ──────────────────
step "Assigning Graph API permissions to Managed Identities"

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_SP_ID=$(az ad sp show --id "$GRAPH_APP_ID" --query "id" -o tsv)

assign_app_role() {
  local principal_id="$1"
  local role_id="$2"
  local role_name="$3"

  info "Assigning ${role_name} to principal ${principal_id}..."
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${GRAPH_SP_ID}/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\": \"${principal_id}\", \"resourceId\": \"${GRAPH_SP_ID}\", \"appRoleId\": \"${role_id}\"}" \
    2>/dev/null || warn "Role ${role_name} may already be assigned"
}

if [[ "$DEPLOY_HD" == true && -n "$FUNC_HD_PRINCIPAL" ]]; then
  # UserAuthenticationMethod.ReadWrite.All
  assign_app_role "$FUNC_HD_PRINCIPAL" "50483e42-d915-4231-9639-7fdb7fd190e5" "UserAuthenticationMethod.ReadWrite.All"
  # User.Read.All
  assign_app_role "$FUNC_HD_PRINCIPAL" "df021288-bdef-4463-88db-98f22de89214" "User.Read.All"
  # Directory.Read.All
  assign_app_role "$FUNC_HD_PRINCIPAL" "7ab1d382-f21e-4acd-a863-ba3e13f7da61" "Directory.Read.All"
  # RoleManagement.Read.Directory
  assign_app_role "$FUNC_HD_PRINCIPAL" "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" "RoleManagement.Read.Directory"
  # Mail.Send
  assign_app_role "$FUNC_HD_PRINCIPAL" "b633e1c5-b582-4048-a93e-9f11b44c7e96" "Mail.Send"

  success "Helpdesk Managed Identity permissions assigned"
fi

# ── Step 6: Backend Deployment ─────────────────────────────────────────────
if [[ "$SKIP_BACKEND" == false ]]; then
  step "Deploying backends"

  if [[ "$DEPLOY_SS" == true ]]; then
    info "Deploying Self-Service backend..."
    cd "$REPO_ROOT/selfservice/backend"
    npm ci --production
    func azure functionapp publish "$FUNC_SS_NAME" --javascript
    success "Self-Service backend deployed"
  fi

  if [[ "$DEPLOY_HD" == true ]]; then
    info "Deploying Helpdesk backend..."
    cd "$REPO_ROOT/helpdesk/backend"
    npm ci --production
    func azure functionapp publish "$FUNC_HD_NAME" --javascript
    success "Helpdesk backend deployed"
  fi
else
  step "Skipping backend deployment"
fi

# ── Step 7: Generate Frontend authConfig.js ────────────────────────────────
if [[ "$SKIP_FRONTEND" == false ]]; then
  step "Generating frontend authConfig.js"

  if [[ "$DEPLOY_SS" == true ]]; then
    cat > "$REPO_ROOT/selfservice/frontend/authConfig.js" <<EOF
const msalConfig = {
  auth: {
    clientId: "${CLIENT_ID_SS}",
    authority: "https://login.microsoftonline.com/${TENANT_ID}",
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const apiScopes = ["api://${CLIENT_ID_SS}/Access"];

const apiBaseUrl = "https://${FUNC_SS_HOST}/api";
EOF
    success "Self-Service authConfig.js generated"
  fi

  if [[ "$DEPLOY_HD" == true ]]; then
    cat > "$REPO_ROOT/helpdesk/frontend/authConfig.js" <<EOF
const msalConfig = {
  auth: {
    clientId: "${CLIENT_ID_HD}",
    authority: "https://login.microsoftonline.com/${TENANT_ID}",
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const apiScopes = ["api://${CLIENT_ID_HD}/Access"];

const apiBaseUrl = "https://${FUNC_HD_HOST}/api";
EOF
    success "Helpdesk authConfig.js generated"
  fi

  # ── Step 8: Frontend Deployment ──────────────────────────────────────────
  step "Deploying frontends"

  if [[ "$DEPLOY_SS" == true ]]; then
    info "Deploying Self-Service frontend..."
    cd "$REPO_ROOT/selfservice/frontend"
    swa deploy . --deployment-token "$SWA_SS_TOKEN" --env production
    success "Self-Service frontend deployed"
  fi

  if [[ "$DEPLOY_HD" == true ]]; then
    info "Deploying Helpdesk frontend..."
    cd "$REPO_ROOT/helpdesk/frontend"
    swa deploy . --deployment-token "$SWA_HD_TOKEN" --env production
    success "Helpdesk frontend deployed"
  fi
else
  step "Skipping frontend deployment"
fi

# ── Step 9: Register Redirect URIs ─────────────────────────────────────────
step "Registering redirect URIs"

if [[ "$DEPLOY_SS" == true && -n "$SWA_SS_HOST" ]]; then
  SS_REDIRECT_URI="https://${SWA_SS_HOST}"
  info "Setting redirect URI for Self-Service: ${SS_REDIRECT_URI}"
  az ad app update --id "$CLIENT_ID_SS" --spa-redirect-uris "$SS_REDIRECT_URI"
  success "Self-Service redirect URI set"
fi

if [[ "$DEPLOY_HD" == true && -n "$SWA_HD_HOST" ]]; then
  HD_REDIRECT_URI="https://${SWA_HD_HOST}"
  info "Setting redirect URI for Helpdesk: ${HD_REDIRECT_URI}"
  az ad app update --id "$CLIENT_ID_HD" --spa-redirect-uris "$HD_REDIRECT_URI"
  success "Helpdesk redirect URI set"
fi

# ── Step 10: Admin Consent ─────────────────────────────────────────────────
step "Granting admin consent"

if [[ "$DEPLOY_SS" == true ]]; then
  info "Granting admin consent for Self-Service app..."
  az ad app permission admin-consent --id "$CLIENT_ID_SS" 2>/dev/null || warn "Admin consent for Self-Service may require Global Admin"
fi

if [[ "$DEPLOY_HD" == true ]]; then
  info "Granting admin consent for Helpdesk app..."
  az ad app permission admin-consent --id "$CLIENT_ID_HD" 2>/dev/null || warn "Admin consent for Helpdesk may require Global Admin"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ EphemGate deployment completed successfully!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$DEPLOY_SS" == true ]]; then
  echo -e "${CYAN}Self-Service Portal:${NC}"
  echo -e "  Frontend: ${BOLD}https://${SWA_SS_HOST}${NC}"
  echo -e "  Backend:  ${BOLD}https://${FUNC_SS_HOST}${NC}"
  echo -e "  Client ID: ${CLIENT_ID_SS}"
  echo ""
fi

if [[ "$DEPLOY_HD" == true ]]; then
  echo -e "${CYAN}Helpdesk Portal:${NC}"
  echo -e "  Frontend: ${BOLD}https://${SWA_HD_HOST}${NC}"
  echo -e "  Backend:  ${BOLD}https://${FUNC_HD_HOST}${NC}"
  echo -e "  Client ID: ${CLIENT_ID_HD}"
  echo ""
fi

echo -e "${GREEN}${BOLD}Zero Secrets Architecture – no client secrets, no rotation needed.${NC}"
echo ""
