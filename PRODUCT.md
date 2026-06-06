# Product

## Register

product

## Users

The owner and a few friends and family (roughly 3 people total). New Yorkers who
already know where they want to eat: their list lives in Google Maps saved pins,
not in a discovery feed. The app is personal and sideloaded, not on the App Store.

Primary context: evening, on the couch, phone in one hand, deciding where to eat
tonight, or chasing a hard-to-get reservation that releases on a schedule. The
job is never "find a restaurant"; it is "get a table at a place I already love,
fast, with as few taps as possible," and "never miss a drop."

## Product Purpose

A personal reservation power-tool that fronts the Resy and OpenTable unofficial
APIs behind a clean private server. It does three things:

1. Checks availability across every saved spot at once for a date, time, and party.
2. Books a Resy table in one tap.
3. Watches venues that release tables in scheduled tranches ("drops"), shows the
   entire release window for hand-picking, and can auto-grab a table the instant
   the drop opens.

Success looks like: a table at a place the user actually wants, secured in
seconds, including the reservations that are otherwise impossible to get.

## Brand Personality

Calm, decisive, insider. The voice is plain and direct, fluent in reservation
lingo (Resy, drops, party size) without explaining it. The interface should feel
like quiet competence: the sense of having an edge, not a consumer app shouting
for attention. Delight is reserved for the moment a table is secured.

## Anti-references

- Consumer dining-discovery apps (Resy, OpenTable, Yelp) and their warm-cream,
  serif, food-photography reflex. This is not a discovery app.
- "Fine dining" mood boards: black plus gold plus serif. Cliche and wrong register.
- Gamified booking apps with badges, streaks, mascots.
- Generic AI-tool SaaS: card grids everywhere, the big-number gradient hero metric,
  glassmorphism, decorative gradients.

## Design Principles

1. **Availability is the one loud signal.** Everything else recedes. Color is
   spent only where it carries meaning.
2. **Built for the couch.** One-handed, evening, low-glare. Key actions sit in
   the lower half; the surface is dark and easy on tired eyes.
3. **A power-tool, not a storefront.** Density and speed over decoration. The user
   is an insider who wants the fastest path, not a tour.
4. **Status and action are never confused.** Orange means "do this," green means
   "good / available," amber means "caution," red means "failed." A color never
   does two jobs.
5. **Every state is designed.** Loading, empty, error, success, and edge cases are
   first-class. Trust is earned on the unhappy paths, not the demo path.

## Accessibility & Inclusion

- Target WCAG AA contrast (met by the cool-ink + accent palette).
- Color is never the sole signal: every status color is paired with an icon and a
  word ("OPEN NOW" + dot, "Confirmed" + check, error + triangle).
- Respect Reduce Motion: shimmer and success animations degrade to static.
- Support Dynamic Type and 44pt minimum touch targets in the SwiftUI build.
