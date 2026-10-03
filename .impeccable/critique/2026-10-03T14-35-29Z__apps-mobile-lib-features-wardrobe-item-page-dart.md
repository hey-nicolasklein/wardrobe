---
target: item detail pages
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 3
target_identity: "file:/Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/wardrobe/item_page.dart"
target_fingerprint: "sha256:5e7031f1b5e972b02977a1b64012ea78e4680ab91dd982f9b0acfe3b0379cf1c"
target_path: /Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/wardrobe/item_page.dart
timestamp: 2026-10-03T14-35-29Z
slug: apps-mobile-lib-features-wardrobe-item-page-dart
---
Method: dual-agent (A: design review on simulator · B: detector + static checks)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | "Metadaten prüfen" is bare sage text with no meaning or action (item_page.dart:231-244) |
| 2 | Match System / Real World | 2 | Colors render as raw English ("red, burgundy") in a German UI |
| 3 | User Control and Freedom | 3 | Versions restorable, archive before delete. Collection toggle moves instantly, no undo |
| 4 | Consistency and Standards | 2 | Two selection styles, duplicate "Katalogbild verbessern" entry, green delete |
| 5 | Error Prevention | 2 | Paid sheet hides price. Low-quality result silently replaces HQ image |
| 6 | Recognition Rather Than Recall | 3 | Clear labels. Collection toggle is icon-only |
| 7 | Flexibility and Efficiency | 1 | No next/prev item, colors edited as CSV text |
| 8 | Aesthetic and Minimalist Design | 2 | 7 stacked actions, version explainer appears twice |
| 9 | Error Recovery | 2 | Failures give no cause and no retry |
| 10 | Help and Documentation | 2 | Explainer exists but never states cost |
| **Total** | | **21/40** | **Acceptable** |

## Priority Issues
- [P0] Paid image sheet hides price and balance; quality heading reads "Niedrig" (item_page.dart:1122, 1153)
- [P1] New image can silently downgrade an HQ catalog image (item_page.dart:1059)
- [P1] Action stack has no hierarchy and duplicates actions (item_page.dart:334-449)
- [P1] Archived/no-image state broken: heavy disabled button, active-looking + tile, Inspire still enabled, restore buried (item_page.dart:130, 394-497, 718)
- [P2] Metadata shows raw English colors, CSV editing, dead-end status (item_page.dart:231, 707, 963)

## Minor
Green delete (541), eyebrow not uppercase, feedback chip <44pt and no selected semantics (1176), literal "HQ" (834), version strip fixed 188pt height clips at large text (432), off-scale radii 10/22, Inspire press anim ignores Reduce Motion.
