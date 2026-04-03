import { app } from "@azure/functions";
import { validateToken, requireRole } from "../lib/auth.js";
import { queryAuditLog } from "../lib/audit.js";

export const auditLog = app.http("auditLog", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "audit-log",
  handler: async (request, context) => {
    const user = await validateToken(request);
    if (!user.valid) {
      return { status: user.status, jsonBody: { error: user.error } };
    }

    const roleCheck = requireRole(user, 'Helpdesk.TapAdmin', 'Helpdesk.TapViewer');
    if (!roleCheck.authorized) {
      return { status: roleCheck.status, jsonBody: { error: roleCheck.error } };
    }

    const daysParam = new URL(request.url).searchParams.get("days");
    const days = Math.min(Math.max(parseInt(daysParam || "7", 10), 1), 90);

    try {
      const entries = await queryAuditLog(days);
      return { status: 200, jsonBody: { entries, days } };
    } catch (error) {
      context.error(`Failed to query audit log: ${error.message}`);
      return { status: 500, jsonBody: { error: "Failed to retrieve audit log" } };
    }
  },
});
