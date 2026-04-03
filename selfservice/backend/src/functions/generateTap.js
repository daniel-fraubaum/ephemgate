import { app } from "@azure/functions";
import { validateToken } from "../lib/auth.js";
import { graphClient } from "../lib/graph.js";
import { writeAuditLog } from "../lib/audit.js";

export const generateTap = app.http("generateTap", {
  methods: ["PUT"],
  authLevel: "anonymous",
  route: "generate-tap",
  handler: async (request, context) => {
    const user = await validateToken(request);
    if (!user.valid) {
      return { status: user.status, jsonBody: { error: user.error } };
    }

    const lifetimeMinutes = parseInt(process.env.TAP_LIFETIME_MINUTES || "60", 10);
    const isUsableOnce = process.env.TAP_IS_USABLE_ONCE !== "false";
    const displayTimeout = parseInt(process.env.TAP_DISPLAY_TIMEOUT_SECONDS || "300", 10);

    try {
      const tapBody = {
        lifetimeInMinutes: lifetimeMinutes,
        isUsableOnce: isUsableOnce,
      };

      const result = await graphClient
        .api(`/users/${user.userId}/authentication/temporaryAccessPassMethods`)
        .post(tapBody);

      await writeAuditLog({
        portal: "selfservice",
        targetUPN: user.upn,
        targetId: user.userId,
        action: "SUCCESS",
        tapLifetimeMinutes: lifetimeMinutes,
        tapIsUsableOnce: isUsableOnce,
        clientIp: request.headers.get("x-forwarded-for") || request.headers.get("x-client-ip") || "",
        userAgent: request.headers.get("user-agent") || "",
      });

      context.log(`TAP created successfully for user ${user.upn}`);

      return {
        status: 200,
        jsonBody: {
          temporaryAccessPass: result.temporaryAccessPass,
          lifetimeInMinutes: lifetimeMinutes,
          isUsableOnce: isUsableOnce,
          displayTimeoutSeconds: displayTimeout,
          createdDateTime: result.createdDateTime,
        },
      };
    } catch (error) {
      context.error(`Failed to create TAP for ${user.upn}: ${error.message}`);

      await writeAuditLog({
        portal: "selfservice",
        targetUPN: user.upn,
        targetId: user.userId,
        action: "ERROR",
        denialReason: error.message,
        tapLifetimeMinutes: lifetimeMinutes,
        tapIsUsableOnce: isUsableOnce,
        clientIp: request.headers.get("x-forwarded-for") || request.headers.get("x-client-ip") || "",
        userAgent: request.headers.get("user-agent") || "",
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
