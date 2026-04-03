import { TableClient } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";

const TABLE_NAME = "RateLimitTracking";
const MAX_TAPS_PER_AGENT_PER_HOUR = 10;

let tableClient = null;

function getTableClient() {
  if (tableClient) return tableClient;

  const accountName = process.env.STORAGE_ACCOUNT_NAME;
  if (!accountName) throw new Error("STORAGE_ACCOUNT_NAME is not configured");

  const connectionString = process.env.AzureWebJobsStorage;
  if (connectionString && connectionString !== "UseDevelopmentStorage=true") {
    tableClient = TableClient.fromConnectionString(connectionString, TABLE_NAME);
  } else {
    const url = `https://${accountName}.table.core.windows.net`;
    tableClient = new TableClient(url, TABLE_NAME, new DefaultAzureCredential());
  }

  return tableClient;
}

/**
 * Checks rate limits for the helpdesk agent and target user.
 * Returns { allowed: true } or { allowed: false, reason: "..." }.
 */
export async function checkRateLimit(agentId, targetUserId) {
  const client = getTableClient();
  const now = new Date();
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

  // Check 1: Max TAPs per agent per hour
  const agentEntities = client.listEntities({
    queryOptions: {
      filter: `PartitionKey eq 'agent-${agentId}' and Timestamp ge datetime'${oneHourAgo.toISOString()}'`,
    },
  });

  let agentCount = 0;
  for await (const _entity of agentEntities) {
    agentCount++;
  }

  if (agentCount >= MAX_TAPS_PER_AGENT_PER_HOUR) {
    return {
      allowed: false,
      reason: `Rate limit exceeded: maximum ${MAX_TAPS_PER_AGENT_PER_HOUR} TAP requests per hour`,
    };
  }

  // Check 2: Max 1 active TAP per target user (check if recent TAP exists)
  const targetEntities = client.listEntities({
    queryOptions: {
      filter: `PartitionKey eq 'target-${targetUserId}' and Timestamp ge datetime'${oneHourAgo.toISOString()}'`,
    },
  });

  for await (const entity of targetEntities) {
    const expiresAt = entity.ExpiresAt ? new Date(entity.ExpiresAt) : null;
    if (expiresAt && expiresAt > now) {
      return {
        allowed: false,
        reason: "Target user already has an active TAP",
      };
    }
  }

  return { allowed: true };
}

/**
 * Records a TAP issuance for rate limiting tracking.
 */
export async function recordTapIssuance(agentId, targetUserId, lifetimeMinutes) {
  const client = getTableClient();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + lifetimeMinutes * 60 * 1000);
  const rowKey = `${now.getTime()}-${Math.random().toString(36).slice(2, 8)}`;

  await Promise.all([
    client.createEntity({
      partitionKey: `agent-${agentId}`,
      rowKey,
      TargetUserId: targetUserId,
      ExpiresAt: expiresAt.toISOString(),
    }),
    client.createEntity({
      partitionKey: `target-${targetUserId}`,
      rowKey,
      AgentId: agentId,
      ExpiresAt: expiresAt.toISOString(),
    }),
  ]);
}
