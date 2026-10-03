---
target: home/feed screen on the mobile app
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/feed_page.dart"
target_fingerprint: "sha256:2cf9a6fa0552d95b6f9f8003bcd90f2478d2c7e4bf0c6402190b6270b33510c1"
target_path: /Users/nicolasklein/development/playground/wardrobe/apps/mobile/lib/features/feed/feed_page.dart
timestamp: 2026-10-03T12-03-58Z
slug: apps-mobile-lib-features-feed-feed-page-dart
---
# Critique: FORM iOS feed (apps/mobile/lib/features/feed)

Method: dual-agent. Source-only (simulator app not running; dev build targets production, not launched). Detector does not support Dart; contrast computed from tokens.

## Heuristics: 24/40 (Acceptable)
1 Status 3 (cold start shows empty state) · 2 Real world 3 (Personenreferenz vs Fotocollage) · 3 Control 2 (one-tap paid regenerations) · 4 Consistency 2 (Material on iOS) · 5 Error prevention 2 (no price) · 6 Recognition 2 (hidden reveal) · 7 Efficiency 2 (no long-press/swipe) · 8 Aesthetic 3 (repeating hero) · 9 Recovery 3 · 10 Help 2

## Specificity
Image area (worn/flat, flat lay, reveal) is product-specific. Frame (heart/share/bookmark, caption, hero) is generic Instagram.
Contrast fails: muted #777B72 3.96:1 on paper, 3.51:1 on chrome; unselected view switch 4.12:1. 10pt eyebrow and tab labels. 38pt view switch, 40pt chips.

## Priority issues
- [P1] Paid actions one tap, no price, styled like free ones (feed_page.dart:244-305). Fix: group paid actions, show credits, confirm sheet. /impeccable harden
- [P1] Cold start shows empty state (feed_page.dart:56,111). Fix: skeleton cards while looks == null. /impeccable harden
- [P2] Reveal undiscoverable and unlabeled (look_card.dart:585, flat_lay_widget.dart:270, look_card.dart:375); reveal ignores Reduce Motion (look_card.dart:851). /impeccable onboard + audit
- [P2] Web-port tells: RefreshIndicator, SnackBar, ripple, Material icons, no tab re-tap scroll, delete not destructive, create button scrolls away. /impeccable adapt
- [P2] Instagram footer row, bookmark has no destination. /impeccable distill

## Personas
Casey: top-right + and … , 38pt switch, 200pt hero. Sam: unlabeled photo/garments, motion, clipping wordmark/tab labels. Jordan: empty flash, jargon. Alex: no long-press, 8-button menu.

## Minor
Status bar luminance averages whole photo (cached_media.dart:183-216). Failed card radius. Sheet header doubled. Raw internals in details. Dev copy "Direkt im Test wählen.". No end of feed.

## Questions
Feed as default tab? Paid actions only in composer? Bookmark vs heart?
