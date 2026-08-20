# NAS deployment

The production stack runs API, worker, PostgreSQL, private MinIO storage, and the Expo Web export in Docker Compose. Only the web and API ports bind to loopback. Tailscale is the only intended network entry point.

## First deployment

1. Install Docker Compose and Tailscale on the NAS.
2. Copy `.env.production.example` to `.env.production` and replace every placeholder. Set `FORM_DATA_DIR` to a persistent NAS path.
3. Build and start the stack:

   ```sh
   docker compose --env-file .env.production -f compose.production.yaml up -d --build
   ```

4. Create the first account from a one-off container. Do not put the password in a committed file:

   ```sh
   docker compose --env-file .env.production -f compose.production.yaml run --rm \
     -e ADMIN_ACCOUNT_EMAIL -e ADMIN_ACCOUNT_PASSWORD api \
     npm run accounts:create --workspace=@form/service
   ```

5. Verify the local boundaries:

   ```sh
   set -a
   source .env.production
   set +a
   curl http://127.0.0.1:4143/health/ready
   curl http://127.0.0.1:${FORM_WEB_PORT:-8081}/
   ```

The API and worker apply pending migrations at startup. The worker waits for healthy dependencies and restarts after failures. The API readiness check remains unhealthy until PostgreSQL and object storage are available.

## Tailscale HTTPS

Use the NAS host's Tailscale identity and publish only the loopback web port:

```sh
set -a
source .env.production
set +a
sudo tailscale serve --https=443 http://127.0.0.1:${FORM_WEB_PORT:-8081}
```

Set `PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN`, and `S3_PUBLIC_ENDPOINT` to the resulting HTTPS URL, rebuild the `web`, `api`, and `worker` services, and use that same URL for browser and mobile-web access. `FORM_WEB_PORT` may select another loopback port when `8081` is occupied. The web container proxies `/v1/` to the API and the bucket path to private MinIO so signed URLs remain usable without exposing Docker-internal hostnames. Do not expose ports 4143, 5432, or 9000 through the router or Tailscale Funnel.

## Backup and restore drill

Run the backup script while the stack is healthy and copy its output to separate storage:

```sh
./deploy/backup.sh /volume1/backups/form
```

For a restore drill, use a maintenance window. The restore command stops the stack, moves the current PostgreSQL and object-storage directories to a timestamped recovery directory, restores both backup artifacts, and waits for every service to become healthy:

```sh
FORM_RESTORE_CONFIRMED=true ./deploy/restore.sh /volume1/backups/form/<timestamp>
FORM_VERIFY_EMAIL=<account-email> FORM_VERIFY_PASSWORD=<account-password> ./deploy/verify.sh
```

Before Tailscale Serve is configured, source `.env.production` as shown above and target the loopback boundary with `FORM_VERIFY_ORIGIN=http://127.0.0.1:${FORM_WEB_PORT:-8081} FORM_VERIFY_EMAIL=<account-email> FORM_VERIFY_PASSWORD=<account-password> ./deploy/verify.sh`.

If the NAS itself does not use MagicDNS, pass its current Tailscale address without changing the public origin: `FORM_VERIFY_RESOLVE=<hostname>:443:<tailscale-ip> ./deploy/verify.sh`.

The confirmation variable prevents accidental restores. The previous data remains recoverable next to `FORM_DATA_DIR`; remove it only after verification succeeds. Pass verification credentials at runtime rather than storing them in a tracked file. Verification performs a credentialed browser sign-in and session restore, checks account, Source Photo, and Wardrobe Item counts, and reads every exact private-object version referenced by PostgreSQL. Record the drill timestamp, backup location, recovery location, counts, and verification result.

Backups contain private wardrobe media and customer data. Encrypt them at rest, restrict access, and never commit them to Git.
