import { app } from "@azure/functions";

export const health = app.http("health", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "health",
  handler: async () => {
    return {
      status: 200,
      jsonBody: {
        status: "healthy",
        portal: "helpdesk",
        timestamp: new Date().toISOString(),
      },
    };
  },
});
