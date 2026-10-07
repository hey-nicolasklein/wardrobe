---
target: looks page
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/look_proposals_page.dart"
target_fingerprint: "sha256:7473550a613ad1669f7107d00bca9c15177efdf1b7f94fc9b5e10fbcb2694dff"
target_path: /Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/look_proposals_page.dart
timestamp: 2026-10-06T12-42-15Z
slug: ib-features-feed-look-proposals-page-dart-a62843f0
---
Target: apps/mobile/lib/features/feed/look_proposals_page.dart (source review, no runtime screenshot)
Score 27/40. Detector: 0 findings (no Dart coverage).
P1 three-state piece tap undiscoverable (proposalsTapHint ~:603) -> keep/leave-out popover or tap/long-press, hide hint after first mark.
P1 swipe vocabulary inconsistent (Variante / Andere Variante / Nächstes / Generieren) -> one verb pair "Weiter" / "Das nehme ich" plus credit cost on primary.
P2 "Dein Look" strip taps remove silently (_MarkThumb ~:171-260) -> state-aware semantics label + undo snackbar.
P2 no undo after right swipe that spends credits (_SwipeDeck ~:330) -> 4s undo before render.
P3 badges 18px/10px icon, pin 13px, colour-only cue -> >=22px, keep shape distinction, strikethrough on excluded.
Minor: identical plural forms in proposalsPicked, possibly unused proposalsExcluded, shouted uppercase stamps.
