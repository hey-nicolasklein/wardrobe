---
target: look erstellen screen
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
target_identity: "file:/Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/look_composer_page.dart"
target_fingerprint: "sha256:fdca40619e2e3e75012ec3605ccc70320543c499c0dd8e3e1cc4eacf0fc42894"
target_path: /Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/look_composer_page.dart
timestamp: 2026-10-03T18-07-24Z
slug: lib-features-feed-look-composer-page-dart-56fcf5c8
---
Method: dual-agent. Target: Look composer sheet (look_composer_page.dart). Score 27/40.
Heuristics: 1=3 2=3 3=3 4=2 5=3 6=3 7=3 8=2 9=2 10=3.
P0 Disabled "Look erstellen" button gives no reason (offline, Anprobe w/o photo, unframable "nur diese") look_composer_page.dart:1345-1351. Fix: reason line replaces summary; 0 credits -> "Credits holen".
P1 Settings cards (Bildstil, Bildqualität) push the wardrobe grid below the fold. Fix: collapse to one meta row near footer.
P1 Default occasion label truncated "Überrasch..." at 11pt in 4 columns (occasion_tile.dart:150-162). Fix: shorter label or chip row.
P2 Inspiration/Anprobe toggle hides different requirements (composer_cubit.dart:113). Fix: sublines, show photo slot.
P3 "Niedrig" default quality reads as defect. Fix: "Standard".
Detector: 0 findings, Dart not supported by regex rules (weak evidence). Browser overlay n/a (Flutter).
