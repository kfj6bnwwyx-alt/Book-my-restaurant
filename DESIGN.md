---
name: ResyBooker
description: A personal reservation power-tool for tables you actually want
colors:
  bg: "#16171A"
  surface: "#1F2125"
  surface-2: "#292B30"
  border: "#383B42"
  scrim: "#0D0E10"
  text-primary: "#ECEEF2"
  text-secondary: "#A0A4AD"
  text-muted: "#90949E"
  accent: "#F26A35"
  accent-ink: "#1E1206"
  accent-soft: "#3A2415"
  success: "#58CC8B"
  success-soft: "#1E3A2A"
  amber: "#E0A852"
  amber-soft: "#3A2F1C"
  red: "#E0685C"
  red-soft: "#3A2320"
typography:
  display:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.15
  headline:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Inter, -apple-system, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 700
    letterSpacing: "0.6px"
rounded:
  sm: "12px"
  md: "16px"
  pill: "999px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "22px"
  section: "28px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.md}"
    padding: "15px 16px"
  button-secondary:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.accent}"
    rounded: "{rounded.md}"
    padding: "10px 18px"
  tab-selected:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent}"
    rounded: "24px"
  chip-unselected:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.text-primary}"
    rounded: "10px"
    padding: "9px 14px"
  chip-selected:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    rounded: "10px"
    padding: "9px 14px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "16px"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "14px 16px"
  tag-available:
    backgroundColor: "{colors.success-soft}"
    textColor: "{colors.success}"
    rounded: "{rounded.pill}"
    padding: "5px 11px"
  tag-warning:
    backgroundColor: "{colors.amber-soft}"
    textColor: "{colors.amber}"
    rounded: "{rounded.pill}"
    padding: "5px 11px"
---

# Design System: ResyBooker

## 1. Overview

**Creative North Star: "The Evening Monitoring Tool"**

ResyBooker is not a restaurant app. It is a calm, dark instrument used on the
couch after dark, by someone who already knows where they want to eat and just
wants a table. The whole surface is a cool-tinted ink that is easy on tired eyes,
and onto that ink a single signal lands hard: a table is available. Everything
else, the chrome, the labels, the metadata, sits back in muted neutrals so the
one thing that matters can shout.

It rejects the entire dining-app reflex on purpose. No warm cream, no serif
display, no food photography, no black-and-gold fine-dining mood, no gamified
badges, and none of the generic AI-SaaS furniture (card grids, gradient hero
metrics, glassmorphism). The closest cousin is a monitoring or flight-tracker
tool, not a storefront: dense when it needs to be, fast always, decorated never.

Two accents do all the talking, and they never trade jobs. Signal orange is for
action and selection. Green is the rare, vital "good / available" mark. Amber and
red speak only for caution and failure.

**Key Characteristics:**
- Dark, cool-tinted, low-glare; designed for one hand in the evening.
- One loud signal (availability) on a recessed neutral field.
- Two committed accents with strict, separate jobs.
- Power-tool density and speed over decorative polish.
- Every state designed: loading, empty, error, success, edge.

## 2. Colors

A cool-tinted neutral ink carrying two committed accents and two semantic alerts.

### Primary
- **Signal Orange** (#F26A35): the only action and selection color. Primary
  buttons, selected tabs, selected chips, links, steppers, the day-jump current
  pill, the app icon. Warm and loud against the cool ink so a tap target is never
  ambiguous. Text on orange is **Orange Ink** (#1E1206). **Orange Soft** (#3A2415)
  tints selected-tab and selected-pill backgrounds.

### Secondary
- **Vital Green** (#58CC8B): the "good / available / on" mark, spent sparingly.
  Availability badges, the live "open now" dot, on-toggles, high match scores, and
  the single confirmation check glyph. **Green Soft** (#1E3A2A) backs small status
  tags only, never a full success surface.

### Tertiary
- **Caution Amber** (#E0A852) on **Amber Soft** (#3A2F1C): scheduled-but-not-open
  ("OPENS IN 2d"), match scores that need confirming, a missed auto-book slot.
- **Failure Red** (#E0685C) on **Red Soft** (#3A2320): errors and destructive or
  failed outcomes only.

### Neutral
- **Ink** (#16171A): the app background.
- **Surface** (#1F2125): cards, panels, inputs, the default raised layer.
- **Surface 2** (#292B30): inputs-on-cards, chips, skeleton blocks, and the
  neutral fill for success icon circles.
- **Border** (#383B42): hairline strokes and dividers.
- **Scrim** (#0D0E10): the dimmed backdrop behind presented sheets.
- **Text Primary** (#ECEEF2), **Text Secondary** (#A0A4AD), **Text Muted**
  (#90949E): the three-step text ramp. Muted clears WCAG AA (>=4.5:1) on bg,
  surface, and surface-2, so it is safe for meaning-bearing labels, not only
  decorative text.

### Named Rules
**The Vital Green Rule.** Green is a signal, not a surface. It appears only on
small tags, the live dot, on-toggles, and the confirmation check glyph. Success
icon circles, "armed" callouts, and result cards are NEUTRAL (surface-2 or
surface); the green check is the one mark that carries the meaning. No green
glows. Success headlines are text-primary, never green.

**The Two Jobs Rule.** Orange is action; green is status. A color never does both.
If a selected state and an available state sit on the same screen, one is orange
and one is green, never the same hue.

## 3. Typography

**Display / Body Font:** Inter (with -apple-system, system-ui fallback). On iOS,
the system font is an acceptable substitute.

**Character:** One family carries everything. This is product UI; a display
pairing would add noise. Hierarchy comes from scale and weight, not from a second
typeface.

### Hierarchy
- **Display** (700, 28px, 1.15): the screen title on every primary screen. Held
  constant app-wide so titles feel uniform.
- **Headline** (700, 22px, 1.2): sheet and success headlines ("2 of 3 booked").
- **Title** (700, 17px, 1.25): card titles and venue names.
- **Body** (400, 14px, 1.45): descriptions and supporting copy. Cap prose at
  65 to 75 characters.
- **Label** (700, 12.5px, 0.6px tracking, UPPERCASE): section overlines and
  micro-confirmations ("AVAILABLE", "RESERVATION CONFIRMED").

### Named Rules
**The Constant Title Rule.** Screen titles are always 28/700. They do not scale
per screen; uniformity is what makes the app feel like one tool.

## 4. Elevation

Flat by default, with depth conveyed through tonal layering, not shadows. The ink
recedes, surface lifts, surface-2 lifts again. Borders (1px, #383B42) separate
peers. Shadow is reserved for two genuinely-floating elements: the capsule tab bar
and presented bottom sheets, plus a single soft drop under a toast.

### Shadow Vocabulary
- **Floating chrome** (`0 10px 30px rgba(0,0,0,0.33)`): the bottom tab bar and
  presented sheets only.
- **Toast lift** (`0 8px 24px rgba(0,0,0,0.33)`): the transient confirmation pill.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat at rest; depth is tonal. A shadow
appears only on something that genuinely floats above the content (tab bar, sheet,
toast). No ambient drop shadows on cards.

## 5. Components

### Buttons
- **Shape:** rounded (16px).
- **Primary:** Signal Orange fill, Orange Ink text, full width, 15px vertical
  padding. The single strong call to action per screen.
- **Secondary:** transparent fill, 1px orange border, orange text. Retry and
  alternate actions.
- **Disabled:** surface-2 fill, muted text, no border (see the invalid-import
  action). Never a dimmed orange.
- **Press:** quick opacity dip with ease-out, ~150ms.

### Chips
- **Time / day chips:** surface-2 background, primary text, 10px radius
  (unselected). Selected flips to Signal Orange fill with Orange Ink text. Used
  for time slots and the day-jump strip.
- **Filter chips:** pill, surface-2 unselected, accent-soft + orange when selected.
- **Status tags:** pill, green-soft + green (available), amber-soft + amber
  (caution). Always carry an icon or a word, never color alone.

### Cards / Containers
- **Corner Style:** 16px (12px for compact rows).
- **Background:** Surface, 1px Border.
- **Shadow Strategy:** none at rest (see Elevation).
- **Internal Padding:** 16px.
- **Note:** never nest a card inside a card.

### Inputs / Fields
- **Style:** Surface fill, 1px Border, 16px radius, 14px/16px padding, with a
  small label above in Text Secondary.
- **Error:** the field border shifts to Red and a Red-Soft banner explains the
  problem above it (see the invalid-GeoJSON state).

### Navigation
- **Bottom tab bar:** a floating frosted capsule, inset from the edges, three
  destinations (Tables, Drops, Spots). Selected tab carries an accent-soft pill
  with an orange icon and label; inactive tabs are muted, unfilled.
- **Detail screens:** a back affordance (chevron + label in orange), no tab bar.

### Signature Component: The Drop Grid
The two-week reservation-drop view shows the entire release window. Days stack
vertically; each day's times are chips. A sticky, horizontally-scrollable
day-jump strip rides under the header so the user never scrolls 14 days to reach
one. Selected time chips turn orange (the user's action); the live "open now" dot
and closing countdown are green and neutral respectively.

## 6. Do's and Don'ts

### Do:
- **Do** keep green for vital signals only: tags, the live dot, on-toggles, and the
  confirmation check glyph. Make success icon circles neutral (surface-2) with a
  green check.
- **Do** use Signal Orange for every action and selection, and nothing else.
- **Do** pair every status color with an icon and a word, so color is never the
  sole signal.
- **Do** hold the screen title at 28/700 on every screen.
- **Do** design loading (skeletons), empty, error (with retry), and success states
  for every flow.
- **Do** convey depth tonally; reserve shadow for the tab bar, sheets, and toasts.

### Don't:
- **Don't** drench success moments in green: no full-green circles, no green card
  backgrounds, no green glows, no green headlines.
- **Don't** reach for the dining-app reflex: no warm cream, no serif display, no
  food photography, no black-and-gold fine-dining mood.
- **Don't** ship generic AI-SaaS furniture: no gradient hero metric, no
  glassmorphism, no identical card grids, no gradient text.
- **Don't** use a `border-left` or `border-right` colored stripe as an accent.
- **Don't** let orange and green trade jobs; action is orange, status is green.
- **Don't** nest a card inside a card, or wrap everything in a container.
- **Don't** use em dashes in UI copy.
