// Helpdesk Portal – Auth Configuration
// Copy this file to authConfig.js and fill in the values.
// No client secret needed – uses PKCE flow.

const msalConfig = {
  auth: {
    clientId: "<helpdesk-frontend-app-reg-client-id>",
    authority: "https://login.microsoftonline.com/<tenant-id>",
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

// Scopes for the backend API – matches the "Expose an API" scope on the backend App Registration
const apiScopes = ["api://<backend-app-reg-client-id>/Access"];

const apiBaseUrl = "<function-app-url>/api";

const loginRequest = { scopes: apiScopes };
