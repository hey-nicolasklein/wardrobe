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
   curl http://127.0.0.1:4143/health/ready
   curl http://127.0.0.1:8081/
   ```

The API and worker apply pending migrations at startup. The worker waits for healthy dependencies and restarts after failures. The API readiness check remains unhealthy until PostgreSQL and object storage are available.

## Tailscale HTTPS

Use the NAS host's Tailscale identity and publish only the loopback web port:

```sh
sudo tailscale serve --https=443 http://127.0.0.1:8081
```

Set `PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN`, and `S3_PUBLIC_ENDPOINT` to the resulting HTTPS URL, rebuild the `web`, `api`, and `worker` services, and use that same URL for browser and mobile-web access. The web container proxies `/v1/` to the API and the bucket path to private MinIO so signed URLs remain usable without exposing Docker-internal hostnames. Do not expose ports 4143, 5432, or 9000 through the router or Tailscale Funnel.

## Backup and restore drill

Run the backup script while the stack is healthy and copy its output to separate storage:

```sh
./deploy/backup.sh /volume1/backups/form
```

For a restore drill, use a disposable stack or a maintenance window. Restore `postgres.dump` with `pg_restore` into the PostgreSQL volume, extract `object-storage.tar.gz` into the configured `FORM_DATA_DIR`, start the stack, and run the integration/release checks from the release ticket. Record the timestamp, backup location, restored account, source-photo count, wardrobe-item count, and whether private media downloads successfully.

Backups contain private wardrobe media and customer data. Encrypt them at rest, restrict access, and never commit them to Git.
