import { initTelemetry } from "./lib/telemetry.js";
initTelemetry();

export { generateTapForUser } from "./functions/generateTapForUser.js";
export { searchUser } from "./functions/searchUser.js";
export { auditLog } from "./functions/auditLog.js";
export { health } from "./functions/health.js";
