<#
.SYNOPSIS
    EphemGate – Automated Deployment Script (PowerShell)
.DESCRIPTION
    Deploys infrastructure, backend, and frontend for Self-Service & Helpdesk TAP portals.
.EXAMPLE
    .\deploy.ps1 -Project "ephemgate-prod"
    .\deploy.ps1 -Project "ephemgate-prod" -Location "westeurope" -App "selfservice"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$Location = "germanywestcentral",

    [ValidateSet("selfservice", "helpdesk", "")]
    [string]$App = "",

    [switch]$SkipInfra,
    [switch]$SkipBackend,
    [switch]$SkipFrontend,

    [string]$DomainSS = "",
    [string]$DomainHD = ""
)

$ErrorActionPreference = "Stop"

# ── Helpers ─────────────────────────────────────────────────────────────────
$script:stepNum = 0
function Write-Step {
    param([string]$Message)
    $script:stepNum++
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  Step $($script:stepNum): $Message" -ForegroundColor Blue
    Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Blue
}

function Write-Info    { param([string]$Msg) Write-Host "ℹ  $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "✅ $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "⚠  $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "❌ $Msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

$DeploySS = $true
$DeployHD = $true
if ($App -eq "selfservice") { $DeployHD = $false }
if ($App -eq "helpdesk")    { $DeploySS = $false }

# ── Confirmation ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor White
Write-Host "║          EphemGate – Deployment Configuration              ║" -ForegroundColor White
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor White
Write-Host "║ Project:          $Project" -ForegroundColor Cyan
Write-Host "║ Location:         $Location" -ForegroundColor Cyan
$deployWhat = @()
if ($DeploySS) { $deployWhat += "Self-Service" }
if ($DeployHD) { $deployWhat += "Helpdesk" }
Write-Host "║ Deploy:           $($deployWhat -join ' + ')" -ForegroundColor Cyan
Write-Host "║ Skip Infra:       $SkipInfra" -ForegroundColor Cyan
Write-Host "║ Skip Backend:     $SkipBackend" -ForegroundColor Cyan
Write-Host "║ Skip Frontend:    $SkipFrontend" -ForegroundColor Cyan
if ($DomainSS) { Write-Host "║ Custom Domain SS: $DomainSS" -ForegroundColor Cyan }
if ($DomainHD) { Write-Host "║ Custom Domain HD: $DomainHD" -ForegroundColor Cyan }
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Proceed with deployment? (y/N)"
if ($confirm -notin @("y", "Y")) { Write-Host "Aborted."; exit 0 }

# ── Step 1: Login Check ────────────────────────────────────────────────────
Write-Step "Checking Azure CLI login"
try {
    $account = az account show --query '{name:name, id:id, tenantId:tenantId}' -o json 2>$null | ConvertFrom-Json
} catch {
    Write-Err "Not logged in. Run: az login"
}
if (-not $account) { Write-Err "Not logged in. Run: az login" }
$TenantId = $account.tenantId
$SubName = $account.name
$SubId = $account.id
Write-Success "Logged in to subscription: $SubName ($SubId)"
Write-Info "Tenant ID: $TenantId"

# ── Step 2: Resource Group ─────────────────────────────────────────────────
Write-Step "Resource Group"
$defaultRg = "rg-$Project"
$inputRg = Read-Host "Resource Group name (default: $defaultRg)"
$ResourceGroup = if ($inputRg) { $inputRg } else { $defaultRg }
Write-Info "Using resource group: $ResourceGroup"

# ── Step 3: App Registrations ──────────────────────────────────────────────
Write-Step "Entra ID App Registrations"

function New-AppRegistration {
    param([string]$DisplayName, [string]$Type)

    Write-Info "Creating/updating App Registration: $DisplayName"

    $existingAppId = az ad app list --display-name $DisplayName --query "[0].appId" -o tsv 2>$null
    if ($existingAppId -and $existingAppId -ne "None") {
        Write-Info "App Registration already exists: $existingAppId"
        return $existingAppId
    }

    if ($Type -eq "selfservice") {
        $appId = az ad app create `
            --display-name $DisplayName `
            --sign-in-audience "AzureADMyOrg" `
            --enable-id-token-issuance $false `
            --enable-access-token-issuance $false `
            --required-resource-accesses '[{\"resourceAppId\":\"00000003-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"e1fe6dd8-ba31-4d61-89e7-88639da4683d\",\"type\":\"Scope\"},{\"id\":\"b7887744-6746-4312-813d-72daeaee7e2d\",\"type\":\"Scope\"}]}]' `
            --query "appId" -o tsv
    } else {
        $appId = az ad app create `
            --display-name $DisplayName `
            --sign-in-audience "AzureADMyOrg" `
            --enable-id-token-issuance $true `
            --enable-access-token-issuance $false `
            --required-resource-accesses '[{\"resourceAppId\":\"00000003-0000-0000-c000-000000000000\",\"resourceAccess\":[{\"id\":\"e1fe6dd8-ba31-4d61-89e7-88639da4683d\",\"type\":\"Scope\"},{\"id\":\"37f7f235-527c-4136-accd-4a02d197296e\",\"type\":\"Scope\"},{\"id\":\"14dad69e-099b-42c9-810b-d002981feec1\",\"type\":\"Scope\"},{\"id\":\"64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0\",\"type\":\"Scope\"}]}]' `
            --app-roles '[{\"allowedMemberTypes\":[\"User\"],\"description\":\"Can create TAPs for users and view audit logs\",\"displayName\":\"Helpdesk TAP Admin\",\"isEnabled\":true,\"value\":\"Helpdesk.TapAdmin\"},{\"allowedMemberTypes\":[\"User\"],\"description\":\"Can view TAP audit logs\",\"displayName\":\"Helpdesk TAP Viewer\",\"isEnabled\":true,\"value\":\"Helpdesk.TapViewer\"}]' `
            --query "appId" -o tsv
    }

    Write-Success "Created App Registration: $appId"
    return $appId
}

$ClientIdSS = ""
$ClientIdHD = ""

if ($DeploySS) {
    $ssAppName = "$Project-selfservice"
    $ClientIdSS = New-AppRegistration -DisplayName $ssAppName -Type "selfservice"
}

if ($DeployHD) {
    $hdAppName = "$Project-helpdesk"
    $ClientIdHD = New-AppRegistration -DisplayName $hdAppName -Type "helpdesk"
}

# ── Step 4: Bicep Deployment ───────────────────────────────────────────────
$FuncSSName = "$Project-ss-func"
$FuncHDName = "$Project-hd-func"
$SwaSSName = "$Project-ss-swa"
$SwaHDName = "$Project-hd-swa"

if (-not $SkipInfra) {
    Write-Step "Bicep Infrastructure Deployment"

    $bicepParams = @(
        "projectName=$Project"
        "location=$Location"
        "entraTenantId=$TenantId"
        "resourceGroupName=$ResourceGroup"
    )
    if ($ClientIdSS) { $bicepParams += "entraClientIdSS=$ClientIdSS" }
    if ($ClientIdHD) { $bicepParams += "entraClientIdHD=$ClientIdHD" }
    if ($DomainSS) { $bicepParams += "customDomainSS=$DomainSS" }
    if ($DomainHD) { $bicepParams += "customDomainHD=$DomainHD" }

    $deploymentName = "ephemgate-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $deployOutput = az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file "$ScriptDir\main.bicep" `
        --parameters $bicepParams `
        --query "properties.outputs" -o json | ConvertFrom-Json

    $FuncSSHost = $deployOutput.funcSelfServiceHostname.value
    $FuncHDHost = $deployOutput.funcHelpdeskHostname.value
    $SwaSSHost = $deployOutput.swaSelfServiceHostname.value
    $SwaHDHost = $deployOutput.swaHelpdeskHostname.value
    $SwaSSToken = $deployOutput.swaSelfServiceDeploymentToken.value
    $SwaHDToken = $deployOutput.swaHelpdeskDeploymentToken.value
    $FuncSSPrincipal = $deployOutput.funcSelfServicePrincipalId.value
    $FuncHDPrincipal = $deployOutput.funcHelpdeskPrincipalId.value

    Write-Success "Infrastructure deployed successfully"
} else {
    Write-Step "Skipping infrastructure deployment"
    Write-Warn "Using existing resources. Retrieving outputs..."

    $FuncSSHost = az functionapp show -n $FuncSSName -g $ResourceGroup --query "defaultHostName" -o tsv 2>$null
    $FuncHDHost = az functionapp show -n $FuncHDName -g $ResourceGroup --query "defaultHostName" -o tsv 2>$null
    $SwaSSHost = az staticwebapp show -n $SwaSSName -g $ResourceGroup --query "defaultHostname" -o tsv 2>$null
    $SwaHDHost = az staticwebapp show -n $SwaHDName -g $ResourceGroup --query "defaultHostname" -o tsv 2>$null
    $SwaSSToken = az staticwebapp secrets list -n $SwaSSName -g $ResourceGroup --query "properties.apiKey" -o tsv 2>$null
    $SwaHDToken = az staticwebapp secrets list -n $SwaHDName -g $ResourceGroup --query "properties.apiKey" -o tsv 2>$null
    $FuncSSPrincipal = az functionapp identity show -n $FuncSSName -g $ResourceGroup --query "principalId" -o tsv 2>$null
    $FuncHDPrincipal = az functionapp identity show -n $FuncHDName -g $ResourceGroup --query "principalId" -o tsv 2>$null
}

# ── Step 5: Graph API Permissions ──────────────────────────────────────────
Write-Step "Assigning Graph API permissions to Managed Identities"

$graphAppId = "00000003-0000-0000-c000-000000000000"
$graphSpId = az ad sp show --id $graphAppId --query "id" -o tsv

function Set-GraphAppRole {
    param([string]$PrincipalId, [string]$RoleId, [string]$RoleName)

    Write-Info "Assigning $RoleName to principal $PrincipalId..."
    $body = @{
        principalId = $PrincipalId
        resourceId  = $graphSpId
        appRoleId   = $RoleId
    } | ConvertTo-Json -Compress

    try {
        az rest --method POST `
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$graphSpId/appRoleAssignments" `
            --headers "Content-Type=application/json" `
            --body $body 2>$null | Out-Null
    } catch {
        Write-Warn "Role $RoleName may already be assigned"
    }
}

if ($DeployHD -and $FuncHDPrincipal) {
    Set-GraphAppRole -PrincipalId $FuncHDPrincipal -RoleId "50483e42-d915-4231-9639-7fdb7fd190e5" -RoleName "UserAuthenticationMethod.ReadWrite.All"
    Set-GraphAppRole -PrincipalId $FuncHDPrincipal -RoleId "df021288-bdef-4463-88db-98f22de89214" -RoleName "User.Read.All"
    Set-GraphAppRole -PrincipalId $FuncHDPrincipal -RoleId "7ab1d382-f21e-4acd-a863-ba3e13f7da61" -RoleName "Directory.Read.All"
    Set-GraphAppRole -PrincipalId $FuncHDPrincipal -RoleId "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" -RoleName "RoleManagement.Read.Directory"
    Set-GraphAppRole -PrincipalId $FuncHDPrincipal -RoleId "b633e1c5-b582-4048-a93e-9f11b44c7e96" -RoleName "Mail.Send"
    Write-Success "Helpdesk Managed Identity permissions assigned"
}

# ── Step 6: Backend Deployment ─────────────────────────────────────────────
if (-not $SkipBackend) {
    Write-Step "Deploying backends"

    if ($DeploySS) {
        Write-Info "Deploying Self-Service backend..."
        Push-Location "$RepoRoot\selfservice\backend"
        npm ci --production
        func azure functionapp publish $FuncSSName --javascript
        Pop-Location
        Write-Success "Self-Service backend deployed"
    }

    if ($DeployHD) {
        Write-Info "Deploying Helpdesk backend..."
        Push-Location "$RepoRoot\helpdesk\backend"
        npm ci --production
        func azure functionapp publish $FuncHDName --javascript
        Pop-Location
        Write-Success "Helpdesk backend deployed"
    }
} else {
    Write-Step "Skipping backend deployment"
}

# ── Step 7: Generate Frontend authConfig.js ────────────────────────────────
if (-not $SkipFrontend) {
    Write-Step "Generating frontend authConfig.js"

    if ($DeploySS) {
        $ssConfig = @"
const msalConfig = {
  auth: {
    clientId: "$ClientIdSS",
    authority: "https://login.microsoftonline.com/$TenantId",
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const apiScopes = ["api://$ClientIdSS/Access"];

const apiBaseUrl = "https://$FuncSSHost/api";
"@
        $ssConfig | Out-File -FilePath "$RepoRoot\selfservice\frontend\authConfig.js" -Encoding utf8
        Write-Success "Self-Service authConfig.js generated"
    }

    if ($DeployHD) {
        $hdConfig = @"
const msalConfig = {
  auth: {
    clientId: "$ClientIdHD",
    authority: "https://login.microsoftonline.com/$TenantId",
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const apiScopes = ["api://$ClientIdHD/Access"];

const apiBaseUrl = "https://$FuncHDHost/api";
"@
        $hdConfig | Out-File -FilePath "$RepoRoot\helpdesk\frontend\authConfig.js" -Encoding utf8
        Write-Success "Helpdesk authConfig.js generated"
    }

    # ── Step 8: Frontend Deployment ────────────────────────────────────────
    Write-Step "Deploying frontends"

    if ($DeploySS) {
        Write-Info "Deploying Self-Service frontend..."
        Push-Location "$RepoRoot\selfservice\frontend"
        swa deploy . --deployment-token $SwaSSToken --env production
        Pop-Location
        Write-Success "Self-Service frontend deployed"
    }

    if ($DeployHD) {
        Write-Info "Deploying Helpdesk frontend..."
        Push-Location "$RepoRoot\helpdesk\frontend"
        swa deploy . --deployment-token $SwaHDToken --env production
        Pop-Location
        Write-Success "Helpdesk frontend deployed"
    }
} else {
    Write-Step "Skipping frontend deployment"
}

# ── Step 9: Register Redirect URIs ─────────────────────────────────────────
Write-Step "Registering redirect URIs"

if ($DeploySS -and $SwaSSHost) {
    $ssRedirectUri = "https://$SwaSSHost"
    Write-Info "Setting redirect URI for Self-Service: $ssRedirectUri"
    az ad app update --id $ClientIdSS --spa-redirect-uris $ssRedirectUri
    Write-Success "Self-Service redirect URI set"
}

if ($DeployHD -and $SwaHDHost) {
    $hdRedirectUri = "https://$SwaHDHost"
    Write-Info "Setting redirect URI for Helpdesk: $hdRedirectUri"
    az ad app update --id $ClientIdHD --spa-redirect-uris $hdRedirectUri
    Write-Success "Helpdesk redirect URI set"
}

# ── Step 10: Admin Consent ─────────────────────────────────────────────────
Write-Step "Granting admin consent"

if ($DeploySS) {
    Write-Info "Granting admin consent for Self-Service app..."
    try { az ad app permission admin-consent --id $ClientIdSS 2>$null } catch { Write-Warn "Admin consent for Self-Service may require Global Admin" }
}

if ($DeployHD) {
    Write-Info "Granting admin consent for Helpdesk app..."
    try { az ad app permission admin-consent --id $ClientIdHD 2>$null } catch { Write-Warn "Admin consent for Helpdesk may require Global Admin" }
}

# ── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ EphemGate deployment completed successfully!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

if ($DeploySS) {
    Write-Host "Self-Service Portal:" -ForegroundColor Cyan
    Write-Host "  Frontend: https://$SwaSSHost"
    Write-Host "  Backend:  https://$FuncSSHost"
    Write-Host "  Client ID: $ClientIdSS"
    Write-Host ""
}

if ($DeployHD) {
    Write-Host "Helpdesk Portal:" -ForegroundColor Cyan
    Write-Host "  Frontend: https://$SwaHDHost"
    Write-Host "  Backend:  https://$FuncHDHost"
    Write-Host "  Client ID: $ClientIdHD"
    Write-Host ""
}

Write-Host "Zero Secrets Architecture – no client secrets, no rotation needed." -ForegroundColor Green
Write-Host ""
