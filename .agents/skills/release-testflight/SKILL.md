---
name: release-testflight
description: Build, upload, and verify a FORM iOS TestFlight release from this Mac. Use when asked to release or ship the mobile beta, or prepare a TestFlight build. Backend deployment is separate.
---

# Release FORM to TestFlight

Read `docs/testflight.md` for signing, app identity, and first-release evidence.
Run commands from the repository root unless stated otherwise.

## Scope and release selection

- “Release/ship to TestFlight” authorizes upload and distribution to **FORM Internal**.
  A request to prepare/build only stops at the local IPA. Creating this skill is
  not authorization to release a new build.
- Mobile builds use the live backend. If the change needs new API behavior,
  establish backend compatibility before uploading; use the separate
  `deploy-stargate` skill only when backend deployment is authorized.
- Review the mobile diff and current worktree. Include the intended changes and
  report relevant unfinished changes; do not discard, commit, or deploy unrelated
  work as part of this workflow.
- Check App Store Connect for the highest uploaded build number, including
  processing/failed uploads, and choose the next unused number. Keep the current
  marketing version for beta iterations unless the user asks to change it.
  `pubspec.yaml` may still say `0.1.0+1`; never infer the next build from that alone.

## Pipeline

```sh
bash apps/mobile/tool/release-testflight.sh --build-number N --check-only
bash apps/mobile/tool/release-testflight.sh --build-number N
# Optional marketing version: --version 0.2.0
```

The local pipeline checks production config and paid-team signing, runs Flutter
analysis/tests, builds the IPA, verifies the archive identity/signature/Apple
sign-in entitlement, and uploads through `xcodebuild` with the explicit team.
For prepare-only work, run verification and `build-testflight.sh` with explicit
`--build-name` and `--build-number` instead of the upload pipeline.

Production Dart defines must contain no development credentials. Signing stays
in ignored local files and the Mac Keychain. If macOS requests the login password,
ask the user to approve the Keychain prompt; do not extract their password.

Identity: app `6819834922`, bundle `de.nicolasklein.form`, team `4KAD6BZY57`.
The SKU `com.nicolasklein.form` is intentionally different. A cached Xcode
“Personal Team” label does not establish actual enrollment; check the developer
portal if needed. Do not change bundle IDs, create another app, or enroll again
just to work around that label.

## Finish in App Store Connect

Use T3's independent browser preview. Inspect status and open the preview if
needed. Its Apple session is separate from Helium. Respect a request to avoid
moving the user's physical cursor. Browser absence is not a reason to replace it
with mouse automation.

1. Confirm upload success and wait for Apple's processing to finish. Report
   progress during the wait. Upload success alone is not availability to testers.
2. Add accurate build-specific **What to Test** notes from the actual diff.
3. Confirm the exact version/build belongs to **FORM Internal** and Nicolas's
   existing account is its tester. Reuse existing group/tester assignments.
4. Verify internal availability or installation in the UI. “Ready to Submit” on
   the overall build can refer to external Beta App Review; check the internal
   group/tester status before treating it as a blocker.
5. Update release evidence in `docs/testflight.md` and report the version/build,
   group, and verified availability. Do not claim installation unless observed.

External testing requires its own requested scope, beta review details, a real
privacy URL, and dedicated review credentials. Do not invite external people or
publish an App Store version as part of an internal release.

## Failed or interrupted attempts

First inspect the uploaded-build list. If Apple already received the exact build,
resume processing/distribution checks instead of uploading again. Retry transient
failures only after confirming Apple did not accept the package. For a duplicate
build number or changed binary, use a new unused number and rebuild. Stop repeated
retries when the same unchanged error recurs; report the concrete missing input
or Apple state. Preserve the working archive and IPA for diagnosis.
