# Public access for the TestFlight beta

Status 2026-10-01: FORM on stargate is made public with Tailscale Funnel. A Cloudflare
Tunnel on its own domain is the plan for the VPS move (see the end).

Goal: external TestFlight testers reach the production stack without Tailscale. Only
FORM goes public. Every other service on stargate stays on the tailnet.

## Shape

```
iPhone ──HTTPS──▶ Tailscale Funnel relay ──▶ tailscaled on stargate (:8443) ──▶ web:8080 (nginx) ──▶ api / minio
```

- The public URL is the existing one: `https://stargate.stork-platy.ts.net:8443`. Tailnet
  devices reach the same URL directly, so `PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN` and
  `S3_PUBLIC_ENDPOINT` stay unchanged.
- Funnel works per port. `:443` and `:8444` stay tailnet only.
- No router port forwarding, and the home IP stays hidden behind Tailscale's relays.

## Turn it on / off

Needs root, or `sudo tailscale set --operator=$USER` once.

```sh
sudo tailscale funnel --bg --https=8443 http://127.0.0.1:18081   # public
sudo tailscale serve  --bg --https=8443 http://127.0.0.1:18081   # back to tailnet only
tailscale funnel status
```

The tailnet policy already grants stargate the `funnel` node attribute (ports 443, 8443,
10000). The public DNS record can take up to 10 minutes to appear after the first switch.

## Client address and the auth rate limit

`/v1/auth/*` POSTs are limited per client address. Tailscale Serve/Funnel overwrites
`X-Forwarded-For` with the client it saw, then reaches nginx through the Docker gateway.
nginx (`deploy/nginx.conf`) trusts only private hops via `real_ip_recursive` and passes the
result to the API as `X-Real-IP`. The API never reads `X-Forwarded-For` itself, so a client
can't pick its own rate-limit key.

## Limits

- **Bandwidth:** Funnel has non-configurable bandwidth limits that Tailscale doesn't publish.
  Check a real photo upload over mobile data. nginx caps requests at 25 MB.
- **Hostname:** only `*.ts.net`, no custom domain. The URL is tied to stargate. The VPS
  move changes the API URL, which means a new build. TestFlight builds expire after 90 days
  anyway.
- **No edge protection:** no WAF, no edge rate limit, no DDoS filter. The app's own auth
  (Apple/Google ID tokens, sessions, credits, the auth limiter) is the gate.
- **The tailnet name `stork-platy` is public.** It was already visible in the certificate
  transparency logs.

Before inviting external testers:
- `DEV_SIGN_IN` stays unset in `.env.production`.
- `deploy/backup.sh` runs regularly. The data now belongs to more people than Nico.

## App + TestFlight

1. Build the release against the public URL:
   `fvm flutter build ipa --flavor production --dart-define-from-file=.env.production.json`,
   with `FORM_API_BASE_URL=https://stargate.stork-platy.ts.net:8443/` and `APPLE_SIGN_IN=true`
   in that ignored file (same pattern as `.env.development.json`, see `apps/mobile/README.md`).
2. Internal testers (up to 100 App Store Connect users) need no review.
3. External testers need a Beta App Review for the first build of each version. Under Test
   Information → *Sign-in required*, provide a demo account. Give reviewers a password
   account with credits (`set-credits` CLI). Keep stargate online during review.
4. Native Sign in with Apple needs only the App ID capability. It doesn't need a Services ID
   or domain verification.

## Later: Cloudflare Tunnel on the VPS

When FORM moves to a VPS, give it a stable custom domain instead of a `ts.net` name:

- Buy a separate domain at Namecheap so the personal domain on Vercel stays untouched.
  Free on 2026-09-30: `wearform.app`, `formwardrobe.app`, `formlooks.app`,
  `formwardrobe.com`, `formlooks.com`. `.app`/`.com` renew at ~$18–23. Many cheap TLDs
  (`.site`, `.store`, `.shop`, `.fit`, `.style`) jump to $26–67 on renewal.
- Point its nameservers at Cloudflare (Free plan). A tunnel hostname only routes if the zone is
  on Cloudflare
  ([docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/)).
- Create a remotely managed tunnel (Networking → Tunnels), route `form.<domain>` → `web:8080`,
  and run `cloudflare/cloudflared` (pinned tag) as a service in `compose.production.yaml` with
  `TUNNEL_TOKEN` from `.env.production`.
- nginx must then also trust Cloudflare's address. The simplest way is to switch
  `real_ip_header` to `CF-Connecting-IP`.
- Leave Bot Fight Mode off and don't use Cloudflare Access. Both break the native app. Add one
  rate-limit rule on `/v1/auth/` and a cache bypass for `/v1/*` and `/form-private-media/*`.
- Switch `PUBLIC_WEB_ORIGIN`, `WEB_ORIGIN` and `S3_PUBLIC_ENDPOINT` to the new host.

## Sources

- Tailscale Funnel: https://tailscale.com/kb/1223/funnel
- Tunnel DNS routing: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/
- Bot Fight Mode: https://developers.cloudflare.com/bots/get-started/bot-fight-mode/
- TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
