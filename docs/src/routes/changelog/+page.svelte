<script lang="ts">
  import Nav from '$lib/components/Nav.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import { reveal } from '$lib/actions/reveal';
  import { folderHue } from '$lib/palette';
  import { releases, REPO, type Release, type Change, type ChangeKind } from '$lib/changelog';

  const TITLE = 'Changelog — Halo';
  const DESC =
    'Every Halo release, drawn straight from the project’s tagged history — what’s new, what got sharper, and what we fixed. Updated with every release.';

  // Date formatting by hand: parsing 'YYYY-MM-DD' through `new Date()` treats it
  // as UTC midnight and can shift the tagged day in western timezones.
  const MONTHS = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  function humanDate(iso: string): string {
    const [y, m, d] = iso.split('-').map((n) => Number(n));
    if (!y || !m || !d) return iso;
    return `${MONTHS[m - 1]} ${d}, ${y}`;
  }

  // Stable per-release anchor id, also used to label the heading for a11y.
  const slug = (tag: string) => `rel-${tag.replace(/\./g, '-')}`;

  // Each kind maps to a token-driven treatment. Color lives only in the dot and
  // the ring (never the text), so the list reads as type — and `improved`
  // borrows a folder hue so the three states feel like one family with the donut.
  const KIND_META: Record<ChangeKind, { label: string; color: string }> = {
    added: { label: 'Added', color: 'var(--reclaim)' },
    improved: { label: 'Improved', color: folderHue(3) },
    fixed: { label: 'Fixed', color: 'var(--progress)' }
  };

  // Stable order within a release: Added first (the headline news), then
  // Improved, then Fixed — so the eye lands on what's new.
  const KIND_ORDER: Record<ChangeKind, number> = { added: 0, improved: 1, fixed: 2 };

  function ordered(changes: Change[]): Change[] {
    return [...changes].sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
  }

  // The per-release mini-donut node: stroked arc segments whose lengths mirror
  // that release's change mix, in the kind colors — the changelog's halo
  // identity in miniature. Pure geometry so the markup stays declarative.
  interface Arc {
    color: string;
    /** stroke-dasharray: drawn length + the remaining gap, in user units */
    dash: string;
    /** stroke-dashoffset that rotates this segment to its slot */
    offset: number;
  }

  const RING_R = 13;
  const RING_C = 2 * Math.PI * RING_R;
  const RING_GAP = 5; // user-units of breathing room between arc segments

  function ringArcs(r: Release): Arc[] {
    const kinds = ordered(r.changes).map((c) => c.kind);
    const n = kinds.length || 1;
    const seg = RING_C / n;
    let acc = 0;
    return kinds.map((kind) => {
      const len = Math.max(seg - RING_GAP, 1);
      const offset = -acc;
      acc += seg;
      return {
        color: KIND_META[kind].color,
        dash: `${len} ${RING_C - len}`,
        offset
      };
    });
  }

  const lastIndex = releases.length - 1;
</script>

<svelte:head>
  <title>{TITLE}</title>
  <meta name="description" content={DESC} />
  <link rel="canonical" href="https://halodisk.app/changelog" />

  <meta property="og:type" content="website" />
  <meta property="og:title" content={TITLE} />
  <meta property="og:description" content={DESC} />
  <meta property="og:url" content="https://halodisk.app/changelog" />
  <meta property="og:image" content="https://halodisk.app/og.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:alt" content="Halo — a disk-space visualizer for macOS" />

  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={TITLE} />
  <meta name="twitter:description" content={DESC} />
  <meta name="twitter:image" content="https://halodisk.app/og.png" />
  <meta name="twitter:image:alt" content="Halo — a disk-space visualizer for macOS" />
</svelte:head>

<Nav />

<main class="page">
  <!-- Drifting color blobs, same grammar as the Features section. -->
  <div class="blobs" aria-hidden="true">
    <div class="blob b1" style:background={folderHue(0)}></div>
    <div class="blob b2" style:background={folderHue(2)}></div>
    <div class="blob b3" style:background={folderHue(5)}></div>
  </div>

  <header class="hero wrap">
    <p class="label" use:reveal>Release notes</p>
    <h1 use:reveal={{ delay: 80 }}>Changelog</h1>
    <p class="sub" use:reveal={{ delay: 160 }}>
      Drawn straight from Halo&rsquo;s tagged history — what&rsquo;s new, what got sharper, and what
      we fixed. Updated with every release, newest first.
    </p>
  </header>

  <div class="wrap">
    <ol class="timeline">
      {#each releases as r, i (r.tag)}
        {@const hue = folderHue(i)}
        {@const arcs = ringArcs(r)}
        <li class="release" id={slug(r.tag)} aria-labelledby={`${slug(r.tag)}-h`} style:--hue={hue}>
          <!-- Left anchor: the version is a hero-scale heading; the mini-ring
               node encodes this release's change mix and threads to the next. -->
          <div class="anchor">
            <span class="node" aria-hidden="true">
              <svg viewBox="0 0 36 36" width="34" height="34">
                <circle class="node-track" cx="18" cy="18" r={RING_R} fill="none" stroke-width="3" />
                {#each arcs as arc, ai (ai)}
                  <circle
                    cx="18"
                    cy="18"
                    r={RING_R}
                    fill="none"
                    stroke={arc.color}
                    stroke-width="3"
                    stroke-linecap="round"
                    stroke-dasharray={arc.dash}
                    stroke-dashoffset={arc.offset}
                    transform="rotate(-90 18 18)"
                  />
                {/each}
              </svg>
              <span class="node-core" style:background={hue}></span>
            </span>

            <h2 class="version-h" id={`${slug(r.tag)}-h`}>
              <a class="version" href={`${REPO}/releases/tag/${r.tag}`} target="_blank" rel="noopener">
                <span class="vnum">{r.version}</span>
                <span class="vtag">{r.tag}</span>
              </a>
            </h2>

            <div class="meta">
              <time class="date" datetime={r.date}>{humanDate(r.date)}</time>
              {#if i === 0}
                <span class="flag latest">Latest</span>
              {:else if i === lastIndex}
                <span class="flag first">First release</span>
              {/if}
            </div>
          </div>

          <!-- Right column: airy change list, ordered Added → Improved → Fixed. -->
          <ul class="changes">
            {#each ordered(r.changes) as c (c.text)}
              <li class="change">
                <span class="tag" style:--c={KIND_META[c.kind].color} data-kind={c.kind}>
                  <span class="dot" aria-hidden="true"></span>
                  {KIND_META[c.kind].label}
                </span>
                <span class="text"
                  >{c.text}{#if c.pr}<a
                      class="pr"
                      href={`${REPO}/pull/${c.pr}`}
                      target="_blank"
                      rel="noopener"
                      aria-label={`Pull request #${c.pr} on GitHub`}>#{c.pr}</a
                    >{/if}</span
                >
              </li>
            {/each}
          </ul>
        </li>
      {/each}
    </ol>

    <p class="foot-note" use:reveal>
      Halo updates itself via Sparkle, signed and notarized — newer builds arrive quietly. The full
      history lives on
      <a href={`${REPO}/releases`} target="_blank" rel="noopener">GitHub Releases</a>.
    </p>
  </div>
</main>

<Footer />

<style>
  .page {
    position: relative;
    background: radial-gradient(ellipse 90% 55% at 50% 0%, var(--void) 0%, var(--void-edge) 100%);
    padding: 138px 0 120px;
    overflow: clip;
  }

  /* ---- Backdrop blobs (Features grammar) ---- */
  .blobs {
    position: absolute;
    inset: 0 0 auto 0;
    height: 720px;
    filter: blur(120px);
    opacity: var(--blob-opacity);
    pointer-events: none;
  }

  .blob {
    position: absolute;
    width: 460px;
    height: 460px;
    border-radius: 50%;
  }

  .b1 {
    top: -12%;
    left: -10%;
    animation: drift1 28s ease-in-out infinite alternate;
  }
  .b2 {
    top: 8%;
    right: -12%;
    animation: drift2 34s ease-in-out infinite alternate;
  }
  .b3 {
    top: 30%;
    left: 34%;
    width: 360px;
    height: 360px;
    animation: drift1 40s ease-in-out infinite alternate-reverse;
  }

  @keyframes drift1 {
    to {
      transform: translate(100px, 64px) scale(1.12);
    }
  }
  @keyframes drift2 {
    to {
      transform: translate(-86px, -56px) scale(0.92);
    }
  }

  /* ---- Hero / masthead ---- */
  .hero {
    position: relative;
    margin-bottom: clamp(56px, 8vw, 92px);
  }

  .label {
    /* `.label` is global; ensure it stacks above the heading. */
    display: block;
  }

  h1 {
    font-size: clamp(44px, 8vw, 80px);
    font-weight: 200;
    letter-spacing: -0.03em;
    line-height: 1.02;
    color: var(--ink);
    margin: 14px 0 0;
  }

  .sub {
    font-size: clamp(16px, 2.1vw, 19px);
    font-weight: 300;
    line-height: 1.55;
    color: var(--ink2);
    max-width: 52ch;
    margin: 20px 0 0;
  }

  /* ---- Timeline ---- */
  .timeline {
    position: relative;
    list-style: none;
    margin: 0;
    padding: 0;
  }

  /* Each release is an editorial row: a hero-scale version numeral anchors the
     left column, the changes breathe in the right. Hairline rules between rows
     are the only chrome — the type does the work. */
  .release {
    --rowpad: clamp(40px, 6vw, 60px);
    position: relative;
    display: grid;
    grid-template-columns: minmax(180px, 232px) 1fr;
    gap: clamp(28px, 6vw, 80px);
    padding: var(--rowpad) 0;
    border-top: 1px solid var(--hairline);
  }

  .release:first-child {
    border-top: 0;
    padding-top: 0;
  }

  /* The thread: a faint vertical line through the gutter linking each node to
     the next. Anchored to the node centers (top = node center, bottom reaches
     into the next row by exactly the next node's offset) so it connects cleanly
     no matter how tall a release row grows — e.g. the 8-item founding release. */
  .release::before {
    content: '';
    position: absolute;
    left: 16px;
    width: 2px;
    top: calc(var(--rowpad) + 19px);
    bottom: calc(-1 * (var(--rowpad) + 19px));
    background: linear-gradient(var(--hairline-strong), var(--hairline));
    border-radius: 2px;
    pointer-events: none;
  }

  .release:first-child::before {
    top: 19px;
  }

  .release:last-child::before {
    display: none;
  }

  /* ---- Left anchor ---- */
  .anchor {
    position: relative;
    padding-left: 50px;
  }

  /* The mini-ring node sits in the gutter, centered on the thread. */
  .node {
    position: absolute;
    left: 0;
    top: 2px;
    display: inline-grid;
    place-items: center;
    width: 34px;
    height: 34px;
  }

  .node svg {
    display: block;
  }

  .node-track {
    stroke: var(--hairline-strong);
  }

  .node-core {
    position: absolute;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    box-shadow: 0 0 10px var(--hue, var(--reclaim));
  }

  .version-h {
    margin: 0;
    font-weight: 400;
    line-height: 1;
  }

  .version {
    display: inline-flex;
    flex-direction: column;
    gap: 4px;
    text-decoration: none;
    transition: color var(--dur-2) var(--ease-out-quart);
  }

  .vnum {
    font-size: clamp(40px, 5.2vw, 58px);
    font-weight: 200;
    letter-spacing: -0.03em;
    line-height: 0.95;
    color: var(--ink);
    font-variant-numeric: tabular-nums;
    transition: color var(--dur-2) var(--ease-out-quart);
  }

  .vtag {
    font-size: 12px;
    font-weight: 500;
    letter-spacing: 0.07em;
    color: var(--ink4);
    transition: color var(--dur-2) var(--ease-out-quart);
  }

  /* Hover recolors to the signature amber (theme-tuned for contrast), not a
     raw folder hue — the per-release hue still lives in the node ring + core. */
  @media (hover: hover) {
    .version:hover .vnum {
      color: var(--reclaim);
    }
    .version:hover .vtag {
      color: var(--ink3);
    }
  }

  .meta {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px 12px;
    margin-top: 16px;
  }

  .date {
    font-size: 13px;
    font-weight: 400;
    letter-spacing: 0.01em;
    color: var(--ink3);
  }

  .flag {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    padding: 4px 10px;
    border-radius: 999px;
    white-space: nowrap;
  }

  .flag.latest {
    color: oklch(0.16 0.02 58);
    background: var(--reclaim);
  }

  .flag.first {
    color: var(--ink3);
    border: 1px solid var(--hairline-strong);
  }

  /* ---- Right column: change list ---- */
  .changes {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .change {
    display: grid;
    grid-template-columns: 104px 1fr;
    align-items: baseline;
    gap: 18px;
  }

  /* The kind is a quiet inline tag: color lives in the dot, the word stays
     neutral, so the list reads as type — not a status board. */
  .tag {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
    color: var(--ink3);
    user-select: none;
    white-space: nowrap;
  }

  .tag .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    flex: none;
    background: var(--c);
    box-shadow: 0 0 8px color-mix(in oklch, var(--c) 55%, transparent);
  }

  .text {
    font-size: clamp(16px, 1.9vw, 18px);
    font-weight: 300;
    line-height: 1.5;
    color: var(--ink);
  }

  .pr {
    margin-left: 9px;
    font-size: 13px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    color: var(--ink4);
    text-decoration: none;
    white-space: nowrap;
    border-bottom: 1px solid transparent;
    transition:
      color var(--dur-2) var(--ease-out-quart),
      border-color var(--dur-2) var(--ease-out-quart);
  }

  @media (hover: hover) {
    .pr:hover {
      color: var(--reclaim);
      border-color: var(--reclaim);
    }
  }

  /* ---- Foot note ---- */
  .foot-note {
    margin: clamp(48px, 7vw, 72px) 0 0;
    padding-top: 32px;
    border-top: 1px solid var(--hairline);
    max-width: 64ch;
    font-size: 14px;
    font-weight: 300;
    line-height: 1.6;
    color: var(--ink3);
  }

  .foot-note a {
    color: var(--ink2);
    text-decoration: none;
    border-bottom: 1px solid var(--hairline-strong);
    transition:
      color var(--dur-2) var(--ease-out-quart),
      border-color var(--dur-2) var(--ease-out-quart);
  }

  @media (hover: hover) {
    .foot-note a:hover {
      color: var(--ink);
      border-color: var(--reclaim);
    }
  }

  /* ---- Responsive: stack the anchor above the changes ---- */
  @media (max-width: 720px) {
    .release {
      grid-template-columns: 1fr;
      gap: 26px;
      padding: var(--rowpad) 0;
    }

    /* Once stacked, the changes claim the full width, so the gutter thread
       would collide with them — drop it and let the hairline rules separate. */
    .release::before {
      display: none;
    }

    .vnum {
      font-size: clamp(38px, 12vw, 50px);
    }
  }

  @media (max-width: 460px) {
    .anchor {
      padding-left: 44px;
    }

    .change {
      grid-template-columns: 1fr;
      gap: 6px;
    }

    .tag {
      font-size: 11px;
    }
  }
</style>
