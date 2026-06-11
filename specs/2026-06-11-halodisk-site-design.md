# halodisk.app — one-pager marketing site design

**Date:** 2026-06-11
**Status:** Approved

> Note: specs live in `specs/` (not the superpowers default `docs/superpowers/specs/`)
> because `docs/` is the SvelteKit site's project root in this repo.

## Goal

A bold, Apple-keynote-feel one-pager for **Halo** (macOS disk-space visualizer) at
**halodisk.app**. Built with SvelteKit, deployed to GitHub Pages. Design direction:
**"Void & Glow" hero + "Liquid Glass" body** — dark-only.

## Decisions

| Question | Decision |
|---|---|
| Location | SvelteKit project source in `docs/` of this repo |
| Deploy | GitHub Pages via Actions (Pages source = "GitHub Actions"); no build output committed |
| Appearance | Dark-only |
| Hero visual | Animated SVG donut (rebuilt, not screenshot) **plus** one real app screenshot in the how-it-works section |
| Sections | Hero, glass nav pill, features, how-it-works, footer/FAQ |
| Dependencies | Zero runtime deps — no Tailwind/GSAP/chart lib; vanilla CSS + hand-rolled SVG |

## Page structure (single route `/`)

1. **Hero** — full viewport, near-black. Centered animated SVG donut (~420px) with
   soft radial halo glow. "Halo" wordmark; headline *"See what's eating your disk."*;
   subline *"A beautiful, blazing-fast disk-space visualizer for macOS."*;
   **Download for Mac** CTA → `https://github.com/amir20/Halo.app/releases/latest/download/Halo.dmg`;
   caption *"Free & open source · macOS 26+ · Apple Silicon"*; scroll chevron.
2. **Nav pill** — hidden over the hero; frosted pill fades in at top center after the
   hero scrolls out (sentinel + IntersectionObserver). Logo-dot, Features,
   How it works, GitHub, compact Download.
3. **Features** — 4 frosted-glass cards over slowly drifting blurred color blobs:
   - **Blazing fast** — parallel scan, one shared work queue
   - **Two lenses** — by folder / by type
   - **Reclaim space** — finds caches, node_modules, DerivedData…
   - **Native & private** — SwiftUI, no telemetry, scans never leave your Mac
4. **How it works** — real dark-mode app screenshot in a glass window frame with a
   scroll-driven 3D straighten effect; 2–3 captioned beats (scan streams in live →
   hover the donut → reclaim with one click).
5. **Footer** — FAQ one-liners (requirements; "is it safe?" → moves items to Trash;
   auto-updates via Sparkle), GitHub link, "Made by Amir Raminfar", © halodisk.app.

## The donut (hero centerpiece)

Hand-built SVG, ~10 arc segments shaped like a plausible scan (one ~30% arc,
descending tail). Colors are the app's real folder-lens palette as native CSS
`oklch()`: hues step by the golden angle 137.507764° from a 35° start, at the
dark-mode lightness/chroma `oklch(0.72 0.125 h)` (see `Sources/Halo/Palette.swift`).

Load animation sequence:
1. Arcs sweep in sequentially around the ring (stroke-dashoffset, ~1.2 s total, ease-out) — reads as a scan completing.
2. Halo glow breathes in behind it (radial gradient, opacity + scale).
3. Center label counts up to a final size ("482 GB"), tabular numerals.
4. Idle: imperceptible ring rotation (~1°/s) + gentle glow pulse.

Pointer parallax: donut tilts a few degrees toward the cursor (transform-only, GPU).

## Visual system

- **Background:** hero `oklch(0.12 0.005 75)` deepening to black; later sections `oklch(0.17 0.005 75)` (the app's dark bg).
- **Ink scale (CSS custom properties), from Palette.swift dark values:** `oklch(0.93 0.006 80)`, `0.76`, `0.60`, `0.48`.
- **Glass:** `backdrop-filter: blur(24px) saturate(1.4)`; 1px hairline border (white 12%); inner top highlight; 20–24px radii.
- **Blobs:** 3–4 giant blurred circles in folder hues drifting on slow keyframe loops behind glass sections.
- **Type:** system stack (`-apple-system`/SF Pro), thin/light display weights, tight tracking. No webfonts.
- **Accent/CTA:** the app's reclaim orange `oklch(0.74 0.16 58)`.
- **Accessibility:** all load/scroll/idle animation respects `prefers-reduced-motion` (arcs render complete, no drift/rotation).

## Scroll animation

- Sections fade + rise (~24px) into view; children stagger 80 ms apart. One small
  `IntersectionObserver` Svelte action (`use:reveal`).
- Screenshot showpiece: starts scaled-down/tilted in 3D perspective, straightens as
  the section scrolls through — CSS scroll-driven animation
  (`animation-timeline: view()`) with the IO-based fallback.
- No scroll-jacking.

## Architecture

- SvelteKit 2 + Svelte 5, `@sveltejs/adapter-static`, `export const prerender = true`
  — fully static output. Dev deps only (svelte, kit, vite, svelte-check, typescript).
- Components: `Hero.svelte`, `Donut.svelte`, `Nav.svelte`, `Features.svelte`,
  `GlassCard.svelte`, `HowItWorks.svelte`, `Footer.svelte`; actions `reveal.ts`
  (IO reveal) and parallax; `palette.css` (oklch tokens ported from Palette.swift).
- Assets in `docs/static/`: app screenshot (WebP + PNG fallback, captured manually
  in dark mode), og-image PNG (donut artwork), favicon derived from
  `Icons/AppIcon.icns` artwork, `CNAME`, `robots.txt`.
- SEO/meta: OpenGraph + Twitter card, canonical URL `https://halodisk.app/`.

## Repo layout & deployment

```
docs/                  # SvelteKit project root
  src/...
  static/              # CNAME, screenshot, og-image, favicon, robots.txt
  package.json, svelte.config.js, vite.config.ts
.github/workflows/site.yml
```

- `docs/static/CNAME` contains `halodisk.app` (adapter-static copies it into the build).
- Site lives at the domain root — no base path config.
- **`site.yml`:** on push to `main` with `paths: [docs/**]` + `workflow_dispatch`:
  checkout → Node 22 + npm cache → `npm ci` → `npm run build` (includes
  `svelte-check` gate) → `actions/upload-pages-artifact` → `actions/deploy-pages`;
  permissions `pages: write`, `id-token: write`.
- **One-time manual steps (user):** Settings → Pages → Source = "GitHub Actions";
  add `halodisk.app` as the custom domain; create DNS records (apex A/AAAA or ALIAS
  to GitHub Pages, HTTPS enforced).
- Download CTA uses `releases/latest/download/Halo.dmg` so the site never needs a
  rebuild per app release (same pattern as the Sparkle appcast).

## Error handling / edge cases

- Browsers without `animation-timeline: view()` → IntersectionObserver fallback.
- Browsers without `backdrop-filter` (rare) → cards fall back to a solid
  semi-opaque dark surface (graceful, still legible).
- `prefers-reduced-motion` → static donut, no drift, instant reveals.
- JS disabled → page is prerendered HTML/CSS; reveals default to visible (CSS
  initial state is visible; the action only adds the hidden state when JS runs).

## Testing

- CI: `svelte-check` + production build must pass before deploy.
- Visual/animation QA: manual, plus Playwright screenshots during development.
- Hover/scroll feel verified by a human (same convention as the app's GUI testing note).
