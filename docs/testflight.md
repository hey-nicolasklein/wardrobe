# TestFlight releases

App Store Connect app: **FORM: Outfit & Kleiderschrank**, Apple ID `6819834922`.
Production bundle ID: `de.nicolasklein.form`. First beta version: `0.1.0`, build `1`.
iPhone only, portrait, iOS 16 or later.

## Local configuration

`apps/mobile/.env.production.json` and
`apps/mobile/ios/Flutter/Signing.local.xcconfig` are ignored local files.
The production API is `https://stargate.stork-platy.ts.net:8443/`.
Set `APPLE_SIGN_IN` to `true`, `DEV_MODE` to `false`, and leave `DEV_EMAIL` and
`DEV_PASSWORD` empty. Dart defines are embedded in the shipped binary.

Signing uses the paid Nicolas Klein team, `4KAD6BZY57`. The old
`7S5WPJ9XT2` personal team cannot export App Store builds. Xcode → Settings →
Apple Accounts must be signed in to the paid team, with an Apple Distribution
certificate and permission to manage provisioning profiles. Native Apple sign-in
uses the `com.apple.developer.applesignin` entitlement.

## Repeatable release flow

Use the repo's [release-testflight skill](../.agents/skills/release-testflight/SKILL.md)
when asking an agent to release the next beta. It covers the local pipeline and
App Store Connect verification. Creating or using the instructions for planning
alone does not upload a build.

1. Review the intended mobile changes and backend compatibility.
2. Check App Store Connect for the next unused build number. Keep `0.1.0` for beta
   iterations; increase the marketing version when appropriate. Numbers are
   explicit so an interrupted upload cannot silently reuse a number.
3. From the repo root, run:

   ```sh
   npm run release:testflight -- --build-number 2 --check-only
   npm run release:testflight -- --build-number 2
   # To change the marketing version too:
   npm run release:testflight -- --build-number 3 --version 0.2.0
   ```

   These numbers are examples, not reservations. The current highest confirmed
   release is `0.1.0 (1)`; check Apple before each upload. The version arguments do
   not modify `pubspec.yaml`. Record the actual release in this guide.
4. The pipeline checks the production config/signing team, runs Flutter analysis
   and tests, builds the IPA, validates the exact archive, and uploads using the
   explicit paid team. It uses the working tree, so review unfinished edits first.
5. Wait for Apple to process the build, write build-specific **What to Test** notes,
   and verify the build and Nicolas's account in **FORM Internal**. Confirm the
   tester can install it. Internal releases need no Beta App Review.

For a local build without upload:

```sh
cd apps/mobile
bash tool/build-testflight.sh --build-name=0.1.0 --build-number=2
```

The archive is at `apps/mobile/build/ios/archive/Runner.xcarchive`; the exported
IPA is at `apps/mobile/build/ios/ipa/FORM.ipa`. The pipeline uses `xcodebuild`
rather than relying on Organizer's cached Personal Team label.
`ITSAppUsesNonExemptEncryption=false` declares standard platform encryption and
HTTPS. Revisit it if custom encryption is introduced.

After an interrupted or failed upload, first check whether Apple already has that
version/build. Resume processing checks for accepted uploads. Rebuild with a new
number for changed binaries; do not blindly repeat an upload.

This is a local pipeline on the signing Mac. A hosted CI pipeline would separately
need a macOS runner, App Store Connect API authentication, signing certificates and
profiles, and secret configuration. None of those credentials are stored in git.

After Apple processes the build, add it to an internal TestFlight group. Internal
testing does not require Beta App Review. External testing requires a complete beta
review contact, a dedicated review account with credits, and first-build review.
Do not use a personal wardrobe account as Apple's demo account.

The **FORM Internal** group is created, with automatic distribution disabled.
Nicolas Klein's App Store Connect account is added as its internal tester.
Build `0.1.0 (1)` is assigned to the group. App Store Connect confirms that
Nicolas installed it on an iPhone 17 running iOS 27.0.1.

## Beta information

The German beta description and feedback email have been saved in App Store Connect.
The description covers clothing intake, wardrobe management, looks, saved results,
and the internet/account requirements. Testers should focus on adding and editing
clothing, archive/restore, and creating/saving looks.

Before external review, supply a real privacy-policy URL, review contact phone
number, and dedicated demo credentials. No privacy-policy page currently exists
in this repository. Keep the public backend online during review; see
[public-access.md](public-access.md).

This first release is for **internal testing**. Beta App Review fields can remain
empty until external testing is requested.

## Verification on 2026-10-06

- `npm run verify:mobile`: analysis clean, all 181 tests passed.
- Production archive and App Store IPA export succeeded (IPA about 26 MB).
- IPA signature verified; paid team `4KAD6BZY57`, Apple sign-in entitlement,
  `beta-reports-active=true`, and `get-task-allow=false` confirmed.
- Public `/v1/meta` responded with contract version 5.
- Flutter reports the existing placeholder launch-image asset. This remains a
  presentation cleanup for a later build.

Build `0.1.0 (1)` was uploaded successfully on 2026-10-06 at 22:26 CEST.
Apple finished processing the package. The build is available for internal testing
and its installation is confirmed in FORM Internal.

The app record originally used `com.nicolasklein.form`. Before upload, it was
changed to `de.nicolasklein.form` to match the signed production app. The SKU
remains `com.nicolasklein.form`; it does not need to match the bundle identifier.
Apple's developer portal confirms that team `4KAD6BZY57` is enrolled as an
individual in the Apple Developer Program, renewing October 7, 2027. Xcode's
cached Personal Team label was stale; uploading through `xcodebuild` with the
explicit paid team succeeded.
