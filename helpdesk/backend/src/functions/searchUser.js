import { app } from "@azure/functions";
import { validateToken, requireRole } from "../lib/auth.js";
import { graphClient } from "../lib/graph.js";

export const searchUser = app.http("searchUser", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "search-user",
  handler: async (request, context) => {
    const user = await validateToken(request);
    if (!user.valid) {
      return { status: user.status, jsonBody: { error: user.error } };
    }

    const roleCheck = requireRole(user, 'Helpdesk.TapAdmin');
    if (!roleCheck.authorized) {
      return { status: roleCheck.status, jsonBody: { error: roleCheck.error } };
    }

    const query = new URL(request.url).searchParams.get("q");
    if (!query || query.trim().length < 2) {
      return { status: 400, jsonBody: { error: "Search query must be at least 2 characters" } };
    }

    const sanitized = query.trim().replace(/'/g, "''");

    try {
      const result = await graphClient
        .api("/users")
        .filter(
          `startsWith(userPrincipalName,'${sanitized}') or startsWith(displayName,'${sanitized}') or startsWith(mail,'${sanitized}')`
        )
        .select("id,userPrincipalName,displayName,givenName,surname,mail,jobTitle,department")
        .top(20)
        .get();

      const users = (result.value || []).map((u) => ({
        id: u.id,
        upn: u.userPrincipalName,
        displayName: u.displayName,
        givenName: u.givenName,
        surname: u.surname,
        mail: u.mail,
        jobTitle: u.jobTitle,
        department: u.department,
      }));

      return { status: 200, jsonBody: { users } };
    } catch (error) {
      context.error(`User search failed for query "${query}": ${error.message}`);
      return { status: 500, jsonBody: { error: "User search failed" } };
    }
  },
});
