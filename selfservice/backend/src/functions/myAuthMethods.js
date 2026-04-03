import { app } from "@azure/functions";
import { validateToken } from "../lib/auth.js";
import { graphClient } from "../lib/graph.js";

export const myAuthMethods = app.http("myAuthMethods", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "my-auth-methods",
  handler: async (request, context) => {
    const user = await validateToken(request);
    if (!user.valid) {
      return { status: user.status, jsonBody: { error: user.error } };
    }

    try {
      const result = await graphClient
        .api(`/users/${user.userId}/authentication/methods`)
        .get();

      const methods = (result.value || []).map((m) => ({
        id: m.id,
        type: m["@odata.type"]?.replace("#microsoft.graph.", "") || "unknown",
      }));

      return { status: 200, jsonBody: { methods } };
    } catch (error) {
      context.error(`Failed to get auth methods for ${user.upn}: ${error.message}`);
      return { status: 500, jsonBody: { error: "Failed to retrieve authentication methods" } };
    }
  },
});
