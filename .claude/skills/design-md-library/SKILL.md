---
name: design-md-library
description: Reference library of 84 DESIGN.md files (from VoltAgent/awesome-design-md, MIT) that describe the design language of well-known websites - Apple, Airbnb, Stripe, Linear, Vercel, Notion, Spotify, Tesla and more - with tokens, typography, color, layout and component rules. Use when the user names one of these sites as a style reference ("que se vea como Stripe", "estilo Apple"), asks for a DESIGN.md, or wants to compare design systems.
---

# DESIGN.md library

Each folder in `sites/` holds a `DESIGN.md` (the design-language analysis) and a `README.md` for one website. The list of sites is the folder names in `sites/`.

## How to use

1. Find the site the user named: list `sites/` and match the folder name (e.g. `sites/stripe/DESIGN.md`, `sites/linear.app/DESIGN.md`).
2. Read only that site's `DESIGN.md`. Do not load the whole library.
3. Use it as a reference for the user's own project: palette, type scale, spacing, components and tone. Keep the user's own content, name, logo and brand. Never copy another company's logo, trademarks, product names or copy, and never present the result as that company's site.
4. If the project should keep the style, write the adapted rules into the project's own `DESIGN.md` (with the user's colors and fonts where they differ), not a copy of the reference.

If the user asks for a site that is not in `sites/`, say so and offer the closest ones in the list.

Source and license: see `README.md` and `LICENSE` in this folder.
