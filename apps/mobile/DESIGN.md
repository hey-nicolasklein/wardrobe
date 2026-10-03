---
name: FORM
description: A warm, paper-and-forest wardrobe app where your clothes are the color.
colors:
  forest: "#344D3F"
  forest-deep: "#263D30"
  linen-paper: "#F6F5F1"
  charcoal-moss: "#242923"
  sage-muted: "#777B72"
  note-ink: "#626E5E"
  hairline: "#E2E4DC"
  chrome: "#E9E8DC"
  field: "#EAECE5"
  pill: "#EEEDE7"
  selected-tint: "#DFE8D2"
  surface: "#FFFFFF"
  brick: "#A34B3C"
  brick-tint: "#F6E9E5"
  coin-gold: "#E2C27E"
  coin-rim: "#C39A62"
  coin-ink: "#7E5F2C"
  coin-tint: "#F7F0DF"
  flat-lay-paper: "#F0EEE6"
  look-stage: "#E7E9E2"
  liked: "#FF7788"
typography:
  display:
    fontFamily: "Libre Baskerville, Georgia, serif"
    fontSize: "43px"
    fontWeight: 400
    lineHeight: 1.08
    letterSpacing: "-1.8px"
  headline:
    fontFamily: "Libre Baskerville, Georgia, serif"
    fontSize: "29px"
    fontWeight: 400
    letterSpacing: "-0.5px"
  title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.55
  small:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 600
    letterSpacing: "2px"
  wordmark:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    letterSpacing: "5px"
rounded:
  badge: "6px"
  input: "12px"
  card: "14px"
  panel: "18px"
  sheet: "25px"
  chip: "30px"
  full: "999px"
spacing:
  gap: "10px"
  grid-column: "13px"
  gutter: "22px"
  grid-row: "22px"
components:
  button-primary:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    rounded: "{rounded.card}"
    padding: "15px 20px"
    height: "50px"
  button-secondary:
    backgroundColor: "{colors.field}"
    textColor: "{colors.forest}"
    rounded: "{rounded.card}"
    padding: "15px 20px"
    height: "50px"
  button-text:
    textColor: "{colors.forest}"
    rounded: "{rounded.card}"
    padding: "12px"
    height: "44px"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.charcoal-moss}"
    rounded: "{rounded.input}"
    padding: "13px"
  input-search:
    backgroundColor: "{colors.field}"
    textColor: "{colors.charcoal-moss}"
    rounded: "{rounded.input}"
  chip-filter:
    backgroundColor: "{colors.linen-paper}"
    textColor: "{colors.charcoal-moss}"
    rounded: "{rounded.chip}"
    padding: "9px 10px"
  chip-filter-selected:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.surface}"
    rounded: "{rounded.chip}"
  pill:
    backgroundColor: "{colors.pill}"
    textColor: "{colors.charcoal-moss}"
    rounded: "{rounded.full}"
    padding: "12px 18px"
    height: "44px"
  pill-selected:
    backgroundColor: "{colors.selected-tint}"
    textColor: "{colors.charcoal-moss}"
    rounded: "{rounded.full}"
  panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.panel}"
    padding: "21px"
  image-card:
    backgroundColor: "{colors.field}"
    rounded: "{rounded.card}"
  notice:
    backgroundColor: "{colors.field}"
    textColor: "{colors.note-ink}"
    rounded: "{rounded.input}"
    padding: "14px 16px"
  notice-error:
    backgroundColor: "{colors.brick-tint}"
    textColor: "{colors.brick}"
    rounded: "{rounded.input}"
    padding: "14px 16px"
  sheet:
    backgroundColor: "{colors.linen-paper}"
    rounded: "{rounded.sheet}"
  tab-bar:
    backgroundColor: "{colors.linen-paper}"
    textColor: "{colors.charcoal-moss}"
---

# Design System: FORM

## Overview

**Creative North Star: "The Linen Closet"**

FORM looks like opening a well-kept closet. Shelves are lined with warm, unbleached paper, everything is folded in its place, and the clothes themselves supply the color. The interface stays in a narrow band of linen, sage and charcoal tones so that every photo of a jacket or sneaker reads as the brightest thing on screen. A single deep forest green marks what you can act on.

Calm does not mean stiff. Inside the order there is warmth and play. Pills spring between options, tabs and buttons sink and bounce back on press, and onboarding pieces can be tossed around. Delight comes from motion and touch, never from loud color or decoration. Serif headlines in Libre Baskerville give the closet a personal, editorial voice. The platform sans does the everyday work.

FORM must never look like stock Material (ripples, elevation shadows, seed-generated tonal palettes), a fast-fashion shop (sale colors, dense product grids, badges everywhere), or a techy AI app (neon gradients, purple glow, decorative sparkles).

**Key Characteristics:**
- Warm off-white paper ground with green-grey neutrals. The clothes provide the color.
- One forest-green accent for actions and selection.
- Serif display headlines over a quiet system sans.
- Flat surfaces separated by tone and hairlines.
- Generous, soft corners from 12 to 25px.
- Springy, haptic micro-motion in place of ripples.

## Colors

A restrained palette of linen, sage and charcoal with a single forest accent. Saturation is kept for the content: garment photos, category tints and color swatches.

### Primary
- **Forest Green** (forest): filled buttons, the round add button, selected filter chips, the sliding segment pill, focused input borders, progress, list icons. It is the one color that means "you can do this". **Forest Deep** (forest-deep) backs toasts.

### Neutral
- **Linen Paper** (linen-paper): scaffold, sheets, dialogs, app bar and the frosted tab bar. The ground everything rests on.
- **Charcoal Moss** (charcoal-moss): all primary text and headlines. A green-tinted near-black, never pure black.
- **Sage Muted** (sage-muted): secondary text, eyebrows, hero summaries.
- **Note Ink** (note-ink): text inside informational notices.
- **Hairline** (hairline): 1px borders on panels, inputs, chips, dividers and the tab bar's top edge.
- **Field** (field): search fields, secondary buttons, notices, image placeholders behind photos.
- **Chrome** (chrome) and **Pill** (pill): slightly warmer resting tones for selected list tiles and unselected pills.
- **Selected Tint** (selected-tint): soft green wash behind a selected pill.
- **Surface White** (surface): text inputs, panels and cards that sit on paper.

### Semantic
- **Brick** (brick) on **Brick Tint** (brick-tint): errors, destructive actions and failed states. Muted terracotta, not alarm red.
- **Coin Gold** family (coin-gold, coin-rim, coin-ink, coin-tint): credits and costs only. Gold means money, nowhere else.
- **Liked** (liked): the heart on a liked look. The only bright warm accent, kept to one icon.

### Content tints
Category, occasion and look-style chips each carry an ink and tint pair (for example sage for tops, dusty rose for bottoms, slate blue for shoes, ochre for accessories). Garment color swatches use softened, slightly greyed versions of each color family. These tints label content and are never used for UI chrome. Source: `FormTokens.category`, `occasions`, `lookStyles`, `colorSwatches`.

### Named Rules
**The Clothes Are the Color Rule.** UI chrome stays inside the linen, sage and charcoal band. If something on screen is more saturated than the garment photos, it has to justify itself.

**The One Green Rule.** Forest green marks actions and selection only. Don't use it for decoration, section backgrounds or illustrations.

**The Gold Means Money Rule.** The coin palette appears only where credits or costs are shown.

## Typography

**Display Font:** Libre Baskerville (bundled, with Georgia and serif as fallback)
**Body Font:** the platform sans (SF Pro on iOS)

**Character:** A bookish, slightly literary serif for the moments that speak to you ("A home for your favourites."), paired with an invisible system sans for everything you operate. The serif is the voice and the sans does the work.

### Hierarchy
- **Display** (400, 43px, 1.08, -1.8px tracking): page heroes. Reduced to 36px inside `FormHero` on tab pages.
- **Headline** (400, 29px, -0.5px): page headers, sheet titles, empty-state titles.
- **Title** (600, 17px): app bar titles and section titles in sans.
- **Body** (400, 14px, 1.55): running text and descriptions. 16px for input text.
- **Small** (400, 12px, 1.6, sage): captions, counts, subtitles, notices.
- **Label / Eyebrow** (600, 10px, 2px tracking, uppercase, sage): the line above a hero headline and small section kickers.
- **Wordmark** (600, 18px, 5px tracking): "FORM", set in widely tracked capitals.
- **Numerals**: tabular figures wherever counts or costs line up.

### Named Rules
**The Serif Speaks, Sans Works Rule.** Libre Baskerville appears only in display and headline roles. Buttons, chips, inputs, labels and lists are always in the platform sans.

**The Quiet Eyebrow Rule.** Every serif hero headline may carry one uppercase sage eyebrow above it. Never stack two, and never put an eyebrow on body content.

## Layout

Single-column phone layout in portrait, inset by a 22px gutter on both sides. Wardrobe and Settings open with a scrolling wordmark and a hero (eyebrow, serif headline, sage summary, optional round add button aligned to the bottom). The Feed has no hero: the wordmark leads straight into the looks, and its add button floats above the tab bar so it stays in reach while you scroll. Content follows in vertical rhythm with 20 to 25px between blocks.

The wardrobe is a two-column grid of tall image cards (aspect 0.54 including caption, 3:4 photos) with 13px between columns and 22px between rows. The generous row gap lets each piece breathe and keeps the grid from feeling like a shop.

Headers and the tab bar float over content. As you scroll, a progressive blur washed with paper fades in under the header, and the tab bar is frosted paper at 85% opacity with a 20px blur. Content stays sharp at rest. Filters dock to the top while scrolling. Sheets rise from the bottom at up to full height, and item detail opens as a draggable sheet over the current tab.

Minimum touch target is 44 × 44px. Primary buttons are 50px tall.

## Elevation & Depth

Flat by default. Surfaces separate through tone (paper, field, white) and 1px hairlines, not shadows. Material elevation, surface tint and ripple overlays are disabled throughout the theme.

Depth appears only for things that actually float above the page:

### Shadow Vocabulary
- **Lifted panel** (`0 6px 18px rgba(29,40,28,0.08)`): a panel that animates into view over the grid, and the floating add button on the feed.
- **Resting knob** (`0 1px 4px rgba(39,55,27,0.04)`): the selected thumb of a segmented switch.
- **Badge lift** (`0 2px 8px rgba(38,53,29,0.07)`): check badges on flat-lay pieces.

All shadows are tinted with green-black, never neutral grey, and stay below 10% opacity.

### Named Rules
**The Flat-By-Default Rule.** A surface at rest has no shadow. A shadow means "this floats" or "this is the one thing to tap".

**The Frosted Paper Rule.** Bars that overlay content use blurred, paper-tinted translucency, never a solid opaque bar or a drop shadow.

## Shapes

Soft and generous. Corners scale with the size of the surface: 6px badges, 12px inputs and notices, 14px buttons and image cards, 18px panels, 25px sheet tops, and full stadium shapes for chips, pills and segmented controls. Primary actions that stand alone, like add, are circles. Pending states use a dashed border instead of a filled tint. Photos are always clipped to the card radius on a field-colored placeholder.

## Components

Warm and playful. Components feel soft to the touch: they sink slightly and spring back on press, selection slides instead of jumping, and light haptics confirm changes. There are no ink ripples anywhere.

### Buttons
- **Shape:** gently rounded rectangle (14px), 50px tall, 15px 20px padding, 15px medium label.
- **Primary:** forest fill with white text. Disabled state is forest at 45% opacity.
- **Secondary:** field fill with forest text, no border.
- **Text:** forest text, 44px minimum target.
- **Round add:** 48px forest circle with a white plus, sitting at the bottom of the hero. On the feed it floats bottom right above the tab bar at 54px with the lifted panel shadow, and hides while the feed is empty, since the empty state carries its own button.
- **Press:** no ripple, no highlight. Feedback comes from scale and opacity and a light haptic.

### Chips
- **Filter chip:** stadium (30px) with hairline border on paper, 13px label. Selected turns solid forest with white text.
- **Pill:** stadium on the pill tone, 44px tall. Selected switches to the soft selected tint without changing the text color.
- **Content chips:** category, occasion and look-style chips use their own ink and tint pair.

### Segmented controls
`FormChoiceChips` and `FormCollectionToggle` (Owning / Wanting): a field-colored stadium track with hairline border, with a selection pill that slides between options (260 to 280ms on the ease-out curve) and a selection haptic. The caption next to the collection toggle cross-fades and slides up as it changes.

### Cards / Containers
- **Image card:** 14px corners, 3:4 by default, field placeholder, no border, no shadow.
- **Panel:** white on paper, 18px corners, 1px hairline, 21px padding.
- **Notice:** field background with note-ink small text, 12px corners. The error variant uses brick on brick tint.
- **Status badge:** 6px corners, 10px semibold label with a 12px icon. Neutral, active (green) and failed (brick) variants.

### Inputs / Fields
- **Text field:** white fill, 1px hairline, 12px corners, 13px padding. Focus switches the border to forest, error to brick.
- **Search field:** field fill, no border, 19px search icon, clear button when filled.

### Navigation
- **Tab bar:** frosted paper with a hairline top edge and custom line icons (feed, closet, settings). Pressing sinks and fades the tab, then springs it back. Switching gives a light impact haptic. The icon animates on selection (520ms).
- **Header:** transparent over a scroll-aware blur. Shows either the tracked wordmark (56px) or a serif headline with an optional small subtitle (76px).
- **Re-tapping the active tab** returns it to its first page and scrolls it to the top.
- **Pull to refresh:** the native iOS refresh control on the feed. The wardrobe still uses Material's indicator and should follow.
- **Transitions:** native Cupertino push on iOS and predictive back on Android. Sheets use a 340ms curve (0.32, 0.72, 0, 1).

### Sheets
Paper background, 25px top corners, 38 × 5px grip, a scrim of green-black at 40%. Draggable and swipe-to-dismiss, scrollable with the keyboard open.

### Dialogs
Destructive confirmations (delete, discard) use the system alert. On iOS the confirm action takes the system's red destructive style and Cancel is the default. On Android the confirm label is brick.

### Paid actions
Every paid generation asks first, in a sheet that says what will happen, what it costs and how many credits are left afterwards. The confirm button names the price ("Erstellen · 2 Credits"), and the composer's create button does the same. With too few credits the button is disabled and the sheet says so in brick. Menus group paid actions under one header that states the cost ("Neu erstellen · je 2 Credits"), apart from free actions like saving and details. Unmetered accounts see the plain action labels.

### Loading
Before the first sync, a list shows placeholders in the shape of its cards (chrome card, look-stage photo area) instead of the empty state. The empty state only appears once the list is known to be empty.

### Inspire Button
The item page's one look action. A flat forest row with 14px corners: the looks icon in a faint white circle, a 15px semibold title, a small subtitle at 75% white and a chevron. No gradient, glow or idle motion. It sinks and springs back on press like the tabs, with a light haptic, and drops to 45% opacity when disabled.

## Do's and Don'ts

### Do:
- **Do** keep chrome inside linen, sage and charcoal so garment photos stay the most colorful thing on screen.
- **Do** use forest green (#344D3F) only for actions, selection and focus.
- **Do** set hero and page headlines in Libre Baskerville, and everything interactive in the platform sans.
- **Do** separate surfaces with tone and 1px hairlines (#E2E4DC) before reaching for a shadow.
- **Do** give touch feedback through sink-and-spring motion and light haptics, and respect Reduce Motion by dropping to instant changes.
- **Do** tint shadows and scrims with green-black (rgba(29,40,28,…)), never neutral grey.
- **Do** keep every tappable control at least 44 × 44px.
- **Do** confirm every paid generation and show its price on the button.

### Don't:
- **Don't** use Material ripples, elevation shadows, surface tint or seed-generated tonal palettes.
- **Don't** make it look like a fast-fashion shop: no loud sale colors, dense product grids or badges on every card.
- **Don't** make it look like a techy AI app: no neon gradients, purple glows or decorative sparkles, including on AI actions.
- **Don't** use pure black (#000) for text or pure grey for neutrals.
- **Don't** use the coin gold palette anywhere except credits and costs.
- **Don't** put the serif on buttons, chips, inputs or labels.
