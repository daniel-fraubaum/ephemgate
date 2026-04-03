import { ManagedIdentityCredential, DefaultAzureCredential } from '@azure/identity';
import { Client } from '@microsoft/microsoft-graph-client';
import {
  TokenCredentialAuthenticationProvider
} from '@microsoft/microsoft-graph-client/authProviders/azureTokenCredentials/index.js';

/**
 * Creates a Microsoft Graph client using Managed Identity.
 * In production: ManagedIdentityCredential (zero secrets).
 * In local dev: falls back to DefaultAzureCredential (az login).
 */
function createGraphClient() {
  const credential = process.env.AZURE_FUNCTIONS_ENVIRONMENT === 'Development'
    ? new DefaultAzureCredential()
    : new ManagedIdentityCredential();

  const authProvider = new TokenCredentialAuthenticationProvider(credential, {
    scopes: ['https://graph.microsoft.com/.default'],
  });

  return Client.initWithMiddleware({ authProvider });
}

const graphClient = createGraphClient();

export { graphClient, createGraphClient };
