import { createGraphClient } from "./graph.js";

/**
 * Hardcoded privileged Entra Directory Role IDs that must never receive a TAP.
 */
const BLOCKED_ROLE_IDS = [
  "62e90394-69f5-4237-9190-012177145e10", // Global Administrator
  "e8611ab8-c189-46e8-94e1-60213ab1f814", // Privileged Role Administrator
  "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", // Privileged Authentication Administrator
  "194ae4cb-b126-40b2-bd5b-6091b380977d", // Security Administrator
  "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", // Application Administrator
  "29232cdf-9323-42fd-ade2-1d097af3e4de", // Exchange Administrator
  "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", // SharePoint Administrator
  "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", // Conditional Access Administrator
];

/**
 * Checks if the target user is privileged and should be blocked from receiving a TAP.
 * Returns { blocked: true, reason: "..." } if blocked, or { blocked: false }.
 */
export async function checkPrivilegedUser(targetUserId) {
  const graphClient = createGraphClient();

  // Check 1: Directory role assignments
  const roleAssignments = await graphClient
    .api(`/roleManagement/directory/roleAssignments`)
    .filter(`principalId eq '${targetUserId}'`)
    .select("roleDefinitionId")
    .get();

  const assignedRoleIds = (roleAssignments.value || []).map((r) => r.roleDefinitionId);
  const blockedRole = assignedRoleIds.find((id) => BLOCKED_ROLE_IDS.includes(id));

  if (blockedRole) {
    const roleName = getRoleName(blockedRole);
    return {
      blocked: true,
      reason: `User has privileged directory role: ${roleName} (${blockedRole})`,
    };
  }

  // Check 2: Blocked group memberships
  const blockedGroupIds = (process.env.BLOCKED_GROUP_IDS || "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);

  if (blockedGroupIds.length > 0) {
    const memberOf = await graphClient
      .api(`/users/${targetUserId}/memberOf`)
      .select("id")
      .get();

    const groupIds = (memberOf.value || []).map((g) => g.id);
    const blockedGroup = groupIds.find((id) => blockedGroupIds.includes(id));

    if (blockedGroup) {
      return {
        blocked: true,
        reason: `User is member of blocked group: ${blockedGroup}`,
      };
    }
  }

  return { blocked: false };
}

function getRoleName(roleId) {
  const names = {
    "62e90394-69f5-4237-9190-012177145e10": "Global Administrator",
    "e8611ab8-c189-46e8-94e1-60213ab1f814": "Privileged Role Administrator",
    "7be44c8a-adaf-4e2a-84d6-ab2649e08a13": "Privileged Authentication Administrator",
    "194ae4cb-b126-40b2-bd5b-6091b380977d": "Security Administrator",
    "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3": "Application Administrator",
    "29232cdf-9323-42fd-ade2-1d097af3e4de": "Exchange Administrator",
    "f28a1f50-f6e7-4571-818b-6a12f2af6b6c": "SharePoint Administrator",
    "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9": "Conditional Access Administrator",
  };
  return names[roleId] || "Unknown Role";
}
