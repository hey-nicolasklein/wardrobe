# Local development access

When starting the application locally, make it reachable through Tailscale as well as localhost.

- Resolve the machine's current Tailscale IPv4 address instead of assuming a fixed address.
- Configure the mobile client's public API URL and the API's allowed web origin to use the same Tailscale host or IP.
- Restart affected development processes after changing environment configuration.
- Verify the web app, API readiness, and browser sign-in/CORS through the Tailscale address.
- Always include the working Tailscale URL and local fixture credentials in the final response.
- Keep secrets out of tracked files; Tailscale-specific runtime values belong in ignored local environment files.
