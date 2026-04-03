import { createGraphClient } from "./graph.js";

/**
 * Sends an email notification to the target user after a TAP has been issued.
 * Uses Microsoft Graph API to send mail from a shared mailbox.
 * If NOTIFICATION_SENDER is not configured, the notification is silently skipped.
 */
export async function sendTapNotification({ targetUPN, agentUPN }) {
  const sender = process.env.NOTIFICATION_SENDER;
  if (!sender) return false;

  const graphClient = createGraphClient();
  const now = new Date().toLocaleString("de-DE", { timeZone: "Europe/Berlin" });

  const message = {
    subject: "Temporary Access Pass wurde für Ihren Account ausgestellt",
    body: {
      contentType: "Text",
      content:
        `Ein Temporary Access Pass wurde für Ihren Account ausgestellt von ${agentUPN} am ${now}. ` +
        `Falls Sie dies nicht angefordert haben, kontaktieren Sie sofort Ihren IT-Support.`,
    },
    toRecipients: [
      {
        emailAddress: { address: targetUPN },
      },
    ],
  };

  try {
    await graphClient.api(`/users/${sender}/sendMail`).post({ message });
    return true;
  } catch (error) {
    console.error(`Failed to send notification to ${targetUPN}: ${error.message}`);
    return false;
  }
}
