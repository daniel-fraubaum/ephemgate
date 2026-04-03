import applicationInsights from "applicationinsights";

let initialized = false;

export function initTelemetry() {
  if (initialized) return;
  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  if (connectionString) {
    applicationInsights.setup(connectionString).setAutoCollectConsole(true).start();
    initialized = true;
  }
}
