import { TableClient } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";
import { randomUUID } from "crypto";

const TABLE_NAME = "TapAuditHelpdesk";
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

export async function writeAuditLog(entry) {
  try {
    const client = getTableClient();
    const now = new Date();
    const partitionKey = now.toISOString().slice(0, 10);
    const rowKey = randomUUID();

    await client.createEntity({
      partitionKey,
      rowKey,
      Portal: entry.portal,
      AgentUPN: entry.agentUPN || "",
      AgentId: entry.agentId || "",
      TargetUPN: entry.targetUPN || "",
      TargetId: entry.targetId || "",
      Action: entry.action,
      DenialReason: entry.denialReason || "",
      TapLifetimeMinutes: entry.tapLifetimeMinutes || 0,
      TapIsUsableOnce: entry.tapIsUsableOnce ?? true,
      ClientIp: entry.clientIp || "",
      UserAgent: entry.userAgent || "",
    });
  } catch (error) {
    console.error("Failed to write audit log:", error.message);
  }
}

export async function queryAuditLog(days = 7) {
  const client = getTableClient();
  const since = new Date();
  since.setDate(since.getDate() - days);
  const sinceStr = since.toISOString().slice(0, 10);

  const entities = client.listEntities({
    queryOptions: {
      filter: `PartitionKey ge '${sinceStr}'`,
    },
  });

  const results = [];
  for await (const entity of entities) {
    results.push({
      timestamp: entity.timestamp,
      portal: entity.Portal,
      agentUPN: entity.AgentUPN,
      agentId: entity.AgentId,
      targetUPN: entity.TargetUPN,
      targetId: entity.TargetId,
      action: entity.Action,
      denialReason: entity.DenialReason,
      tapLifetimeMinutes: entity.TapLifetimeMinutes,
      tapIsUsableOnce: entity.TapIsUsableOnce,
      clientIp: entity.ClientIp,
      userAgent: entity.UserAgent,
    });
  }

  return results.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
}
