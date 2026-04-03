import { createRemoteJWKSet, jwtVerify } from 'jose';

const TENANT_ID = process.env.ENTRA_TENANT_ID;
const CLIENT_ID = process.env.ENTRA_CLIENT_ID;

if (!TENANT_ID || !CLIENT_ID) {
  throw new Error('ENTRA_TENANT_ID and ENTRA_CLIENT_ID must be set');
}

const jwksUri = new URL(
  `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`
);
const jwks = createRemoteJWKSet(jwksUri);

/**
 * Validates a Bearer token from the Authorization header.
 * Uses the Microsoft JWKS endpoint to verify the JWT signature.
 * No client secret required – only public signing keys.
 *
 * @param {import('@azure/functions').HttpRequest} req
 * @returns {Promise<{valid: boolean, status?: number, error?: string, userId?: string, upn?: string, name?: string, roles?: string[]}>}
 */
export async function validateToken(req) {
  const authHeader = req.headers.get('authorization') || req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { valid: false, status: 401, error: 'Missing or invalid Authorization header' };
  }

  const token = authHeader.split(' ')[1];

  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: [
        `https://login.microsoftonline.com/${TENANT_ID}/v2.0`,
        `https://sts.windows.net/${TENANT_ID}/`,
      ],
      audience: [CLIENT_ID, `api://${CLIENT_ID}`],
      clockTolerance: 60,
    });

    return {
      valid: true,
      userId: payload.oid || payload.sub,
      upn: payload.preferred_username || payload.upn || '',
      name: payload.name || '',
      roles: payload.roles || [],
      tenantId: payload.tid,
    };
  } catch (err) {
    return { valid: false, status: 401, error: `Token validation failed: ${err.message}` };
  }
}
