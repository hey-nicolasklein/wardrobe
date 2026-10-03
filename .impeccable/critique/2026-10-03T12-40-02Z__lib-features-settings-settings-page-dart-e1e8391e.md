---
target: settings page
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/settings/settings_page.dart"
target_fingerprint: "sha256:0acb9443afd77f7baa5b0900145192bfb0db60cdad2e495a161f1e55f2a77663"
target_path: /Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/settings/settings_page.dart
timestamp: 2026-10-03T12-40-02Z
slug: lib-features-settings-settings-page-dart-e1e8391e
---
Method: dual-agent (A: a71ad13dc2201360c · B: a84739c2c56673379)
Score 25/40 (Acceptable). Detector: 0 findings (Dart likely not scanned). Browser overlay skipped (native Flutter).
H: 1=3 2=2 3=3 4=2 5=3 6=3 7=2 8=2 9=3 10=2
Priority issues:
[P1] Account deletion weaker guarded than reset: one alert tap, no busy state, dangerTint styling identical to reset (account_section.dart:38-73). Fix: native destructive alert or typed phrase, busy state, inline error, last on page. /impeccable harden
[P1] Debug block (feed weights, replay onboarding) renders unconditionally (settings_page.dart:79-89); self-host copy ("Private via Tailscale", "No password required", Contract, server) ships to App Store users. Fix: gate on kDebugMode, move server details behind ServerPage row, rewrite access copy. /impeccable distill
[P2] Order follows code, not intent; language buried in App Info; archive is a lone OutlinedButton. Fix: You / Preferences / Data / Account groups, iOS rows with chevrons. /impeccable layout
[P2] Three different confirm patterns and soft danger styling (dangerTint + ink). /impeccable polish
[P3] Reset phrase exact match brittle (trim/normalize). /impeccable harden
Minor: footer fontSize 11; hero "All yours." says little; repeated SizedBox(20); archive button shows "0 items"; AccountSection reads isSignedIn without watching.
