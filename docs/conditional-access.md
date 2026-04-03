# Conditional Access Policies

EphemGate should be protected by Conditional Access policies to ensure secure access. Below are the recommended policies for both portals.

## Prerequisites

- Microsoft Entra ID P1 or P2 license
- Conditional Access Administrator or Security Administrator role
- Both App Registrations created and Enterprise Applications (Service Principals) visible

## Policy 1: Self-Service Portal

### Purpose
Ensures that end users accessing the Self-Service TAP portal are using MFA and a compliant device.

### Configuration

| Setting | Value |
|---------|-------|
| **Name** | `EphemGate – Self-Service Portal Access` |
| **State** | Enabled |
| **Users** | All users (or specific groups) |
| **Exclude** | Breakglass accounts |
| **Target resources** | `EphemGate Self-Service` (Enterprise App) |
| **Conditions** | None |
| **Grant** | Require multifactor authentication AND Require device to be marked as compliant |
| **Session** | Sign-in frequency: 1 hour |

### Azure Portal Steps

1. Go to **Entra ID** → **Security** → **Conditional Access** → **Policies**
2. Click **New policy**
3. **Name**: `EphemGate – Self-Service Portal Access`
4. **Assignments**:
   - **Users**: Include → All users; Exclude → Breakglass accounts
   - **Target resources**: Include → Select apps → `EphemGate Self-Service`
5. **Access controls** → **Grant**:
   - ✅ Require multifactor authentication
   - ✅ Require device to be marked as compliant
   - Operator: **AND** (require all selected controls)
6. **Session**:
   - Sign-in frequency: 1 hour
7. **Enable policy**: On
8. Click **Create**

---

## Policy 2: Helpdesk Portal

### Purpose
Ensures that helpdesk agents accessing the Helpdesk TAP portal are using MFA, a compliant device, and are connecting from the corporate network.

### Configuration

| Setting | Value |
|---------|-------|
| **Name** | `EphemGate – Helpdesk Portal Access` |
| **State** | Enabled |
| **Users** | Groups assigned to `Helpdesk.TapAdmin` / `Helpdesk.TapViewer` |
| **Exclude** | Breakglass accounts |
| **Target resources** | `EphemGate Helpdesk` (Enterprise App) |
| **Conditions** | Locations: Exclude → Corporate Network (Named Location) |
| **Grant** | Require MFA AND Require compliant device |
| **Session** | Sign-in frequency: 1 hour |

### Prerequisite: Named Location

Create a Named Location for your corporate network:

1. Go to **Entra ID** → **Security** → **Conditional Access** → **Named Locations**
2. Click **IP ranges location**
3. **Name**: `Corporate Network`
4. Add your corporate public IP ranges
5. Check **Mark as trusted location**
6. Click **Create**

### Azure Portal Steps

1. Go to **Entra ID** → **Security** → **Conditional Access** → **Policies**
2. Click **New policy**
3. **Name**: `EphemGate – Helpdesk Portal Access`
4. **Assignments**:
   - **Users**: Include → Select groups (Helpdesk agents group); Exclude → Breakglass accounts
   - **Target resources**: Include → Select apps → `EphemGate Helpdesk`
   - **Conditions** → **Locations**:
     - Configure: Yes
     - Include: Any location
     - Exclude: `Corporate Network`
5. **Access controls** → **Grant**:
   - ✅ Require multifactor authentication
   - ✅ Require device to be marked as compliant
   - Operator: **AND**
6. **Session**:
   - Sign-in frequency: 1 hour
7. **Enable policy**: On
8. Click **Create**

> **Note**: This policy blocks access from outside the corporate network. The "Include Any location / Exclude Corporate Network" pattern in the Conditions → Locations section means the policy only activates when the user is NOT in the corporate network. Combined with the Grant controls requiring MFA + compliant device, users outside the corporate network will be blocked (they won't satisfy the conditions from an untrusted location).

> **Alternative**: If you want to allow access from outside but still require MFA + compliant device everywhere, remove the Locations condition entirely.

---

## Additional Recommendations

### Block Legacy Authentication
Create a policy to block legacy authentication protocols for both apps:

| Setting | Value |
|---------|-------|
| **Name** | `EphemGate – Block Legacy Auth` |
| **Users** | All users |
| **Target resources** | Both EphemGate apps |
| **Conditions** | Client apps → Other clients, Exchange ActiveSync |
| **Grant** | Block access |

### Require App Protection (Mobile)
If mobile access is needed, consider requiring app protection policies:

| Setting | Value |
|---------|-------|
| **Name** | `EphemGate – Require App Protection` |
| **Users** | All users |
| **Target resources** | Both EphemGate apps |
| **Conditions** | Device platforms → iOS, Android |
| **Grant** | Require app protection policy |

## Testing

Before enabling policies in production:

1. Use **Report-only** mode first to evaluate impact
2. Exclude your **breakglass accounts** from all policies
3. Test with a pilot group before rolling out to all users
4. Monitor sign-in logs for blocked access attempts
