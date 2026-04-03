import { app } from "@azure/functions";
import { validateToken, requireRole } from "../lib/auth.js";
import { graphClient } from "../lib/graph.js";
import { checkPrivilegedUser } from "../lib/privilegedUserGuard.js";
import { checkRateLimit, recordTapIssuance } from "../lib/rateLimiter.js";
import { sendTapNotification } from "../lib/notification.js";
import { writeAuditLog } from "../lib/audit.js";

export const generateTapForUser = app.http("generateTapForUser", {
  methods: ["PUT"],
  authLevel: "anonymous",
  route: "generate-tap/{userId}",
  handler: async (request, context) => {
    const user = await validateToken(request);
    if (!user.valid) {
      return { status: user.status, jsonBody: { error: user.error } };
    }

    const roleCheck = requireRole(user, 'Helpdesk.TapAdmin');
    if (!roleCheck.authorized) {
      return { status: roleCheck.status, jsonBody: { error: roleCheck.error } };
    }

    const targetUserId = request.params.userId;
    if (!targetUserId) {
      return { status: 400, jsonBody: { error: "userId parameter is required" } };
    }

    const clientIp = request.headers.get("x-forwarded-for") || request.headers.get("x-client-ip") || "";
    const userAgent = request.headers.get("user-agent") || "";
    const lifetimeMinutes = parseInt(process.env.TAP_LIFETIME_MINUTES || "120", 10);
    const isUsableOnce = process.env.TAP_IS_USABLE_ONCE !== "false";
    const displayTimeout = parseInt(process.env.TAP_DISPLAY_TIMEOUT_SECONDS || "120", 10);

    const auditBase = {
      portal: "helpdesk",
      agentUPN: user.upn,
      agentId: user.userId,
      targetId: targetUserId,
      tapLifetimeMinutes: lifetimeMinutes,
      tapIsUsableOnce: isUsableOnce,
      clientIp,
      userAgent,
    };

    try {
      // Resolve target user UPN for audit/notification
      let targetUser;
      try {
        targetUser = await graphClient.api(`/users/${targetUserId}`).select("id,userPrincipalName,displayName").get();
      } catch {
        return { status: 404, jsonBody: { error: "Target user not found" } };
      }
      auditBase.targetUPN = targetUser.userPrincipalName;

      // Privileged User Guard
      const guardResult = await checkPrivilegedUser(targetUserId);
      if (guardResult.blocked) {
        context.error(`CRITICAL: Blocked TAP for privileged user ${targetUser.userPrincipalName} by agent ${user.upn}. Reason: ${guardResult.reason}`);

        await writeAuditLog({
          ...auditBase,
          action: "BLOCKED_PRIVILEGED",
          denialReason: guardResult.reason,
        });

        return {
          status: 403,
          jsonBody: { error: "Cannot create TAP for privileged user", reason: guardResult.reason },
        };
      }

      // Rate Limit Check
      const rateResult = await checkRateLimit(user.userId, targetUserId);
      if (!rateResult.allowed) {
        await writeAuditLog({
          ...auditBase,
          action: "RATE_LIMITED",
          denialReason: rateResult.reason,
        });

        return {
          status: 429,
          jsonBody: { error: rateResult.reason },
        };
      }

      // Create TAP
      const tapBody = {
        lifetimeInMinutes: lifetimeMinutes,
        isUsableOnce: isUsableOnce,
      };

      const result = await graphClient
        .api(`/users/${targetUserId}/authentication/temporaryAccessPassMethods`)
        .post(tapBody);

      // Record for rate limiting
      await recordTapIssuance(user.userId, targetUserId, lifetimeMinutes);

      // Send notification
      const notificationSent = await sendTapNotification({
        targetUPN: targetUser.userPrincipalName,
        agentUPN: user.upn,
      });

      // Audit log
      await writeAuditLog({
        ...auditBase,
        action: "SUCCESS",
      });

      context.log(`TAP created for ${targetUser.userPrincipalName} by agent ${user.upn}`);

      return {
        status: 200,
        jsonBody: {
          temporaryAccessPass: result.temporaryAccessPass,
          lifetimeInMinutes: lifetimeMinutes,
          isUsableOnce: isUsableOnce,
          displayTimeoutSeconds: displayTimeout,
          createdDateTime: result.createdDateTime,
          targetUser: {
            id: targetUser.id,
            upn: targetUser.userPrincipalName,
            displayName: targetUser.displayName,
          },
          notificationSent,
        },
      };
    } catch (error) {
      context.error(`Failed to create TAP for ${targetUserId} by agent ${user.upn}: ${error.message}`);

      await writeAuditLog({
        ...auditBase,
        action: "ERROR",
        denialReason: error.message,
      });

      if (error.statusCode === 400) {
        return {
          status: 400,
          jsonBody: { error: "A TAP already exists or cannot be created. Please try again later." },
        };
      }

      return { status: 500, jsonBody: { error: "Failed to create Temporary Access Pass" } };
    }
  },
});
