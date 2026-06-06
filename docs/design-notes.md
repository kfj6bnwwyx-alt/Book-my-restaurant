# Pencil design notes

Reference for the ResyBooker visual design built in Pencil. The design file is
`Pen/Book-my-restaurant` (open via the Pencil MCP; never Read/Grep the `.pen`
directly). The token system and rules are in `DESIGN.md`; the strategy is in
`PRODUCT.md`. This file captures the screen inventory and component ids so the
work is reproducible if you reopen the design.

## Register and frame

Product (mobile app UI), iPhone 390px wide. Screens are top-level frames with
`height: "fit_content(N)"`, `clip: true`.

## Direction

A personal **evening monitoring tool**, deliberately NOT the restaurant-app
reflex (no warm cream, serif, food photography, or black-and-gold fine dining).
Cool-tinted dark ink surface. Inter throughout, uniform 28px titles.

Two-accent system:
- **Orange = actions / selection / brand** (buttons, selected tabs/chips, links).
- **Green = vital signal ONLY**, used sparingly: small tags/pills (availability
  "4 open", "OPEN NOW", "Confirmed", high match score), the live "open now" dot,
  on-toggles, and confirmation check glyphs. Green is NOT used for big surfaces:
  success icon circles are neutral (surface-2) with a green check glyph,
  success/"armed" cards are neutral, no green glows, success headlines are
  text-primary.
- **Amber** = match-confidence "opens in" / needs-confirm. **Red** = errors.

## Tokens (Pencil variables, referenced as `$name`)

bg `#16171A`, surface `#1F2125`, surface-2 `#292B30`, border `#383B42`,
text-primary `#ECEEF2`, text-secondary `#A0A4AD`, text-muted `#686C76`.
accent `#F26A35` (signal orange), accent-ink `#1E1206`, accent-soft `#3A2415`.
success `#58CC8B`, success-soft `#1E3A2A`. amber `#E0A852`, amber-soft `#3A2F1C`,
red `#E0685C`, red-soft `#3A2320`. radius 16, radius-sm 12. Sheet/scrim screens
use `#0D0E10`; the tab bar glass fill is literal `#292B30E6`. (These are the same
values as the SwiftUI `RBColor` tokens in `ios/ResyBooker/DesignSystem/Theme.swift`.)

## Reusable components (Pencil node ids)

- StatusBar `aHDZx`
- PrimaryButton `l1xSxg` (label `Zxn2u`, icon `MKlVR`)
- TabBar `thFOz`, 3 tabs: Tables `nUCqU`, Drops `VmThv`, Spots `s3ypLb` (each has
  an icon + label child)
- PinRow `Z3Km3`, CandidateRow `LrxNU`
- EmptyState `f7vxXb` (icon `H8Q37`, heading `pA6FE`, body `FAEyv`)
- InlineError `lZgRw` (heading `a9vABN`, body `VqTf2`, has a Try-again button)
- Toast `ylORJ` (icon `nJhgx`, text `txBgv`)
- Skeleton `J57PS` (reusable rect for shimmer blocks)

## Screen set (~38 screens)

Original app: Tables (empty / results), Booking Confirm (ready / confirmed),
Spots (list / empty), Import sheet, Link Venue.

Reservation-drop feature: Drops Overview, Drop Countdown, Two-Week Grid (the
hero: entire 14-day window with multi-select time chips and a horizontal
day-jump strip), Auto-book Setup, Review-and-Reserve sheet.

State matrix (for the Xcode build): Tables loading/no-linked-spots/search-error/
none-available; Booking in-progress/failed(slot-taken); Spots loading/load-error;
Import invalid-geojson/success; Link Venue loading/no-candidates(+manual search)/
error; Drops empty; Grid loading/nothing-selected/closed(sold-out); Reserve
in-progress/partial-results(2-of-3); Auto-book result card + Toast; lock-screen
push notification mocks; 4-screen first-run onboarding (welcome / connect-server /
import-spots / done).

Canvas layout (rows by y): originals y=182, drop feature y=1250, state screens
y=2500+, onboarding y=10800. Design Health Score ~37/40.

## SwiftUI mapping

`ios/ResyBooker/DesignSystem/` already implements the foundation: `Theme.swift`
(tokens), `ButtonStyles.swift` (`.rbPrimary` / `.rbSecondary`), `EmptyStateView`,
`InlineErrorView`, `ToastView` (+ `.rbToast`), `SkeletonView`
(`SkeletonBlock` / `SkeletonVenueCard` + `rbShimmer`, respects Reduce Motion),
plus delight: `SuccessCheck` (animated check), `Haptics`, `ChipButtonStyle`.
Build the feature screens on top of these.

## Pencil gotchas

- lucide renamed icons: use `timer` (not `clock`), `circle-check` / `circle-plus`
  / `circle-minus` (not the `-circle` suffixes).
- No text wrapping across a row; split chips into rows of ~4.
- For parallel screen builds, assign fixed non-overlapping x/y (don't let
  subagents race on FindEmptySpace).
