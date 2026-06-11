<script lang="ts">
  import Donut from './Donut.svelte';

  const DMG = 'https://github.com/amir20/Halo.app/releases/latest/download/Halo.dmg';
</script>

<section class="hero" id="top">
  <div class="content">
    <p class="wordmark">Halo</p>
    <h1>See what's eating<br />your disk.</h1>
    <p class="sub">A beautiful, blazing-fast disk-space visualizer for macOS.</p>

    <Donut />

    <div class="cta">
      <a class="download" href={DMG}>
        <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true">
          <path
            d="M8 1v9.3M4.5 7.3 8 10.8l3.5-3.5M2.5 13.5h11"
            fill="none"
            stroke="currentColor"
            stroke-width="1.6"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        Download for Mac
      </a>
      <p class="fine">Free &amp; open source · macOS 26+ · Apple Silicon</p>
    </div>
  </div>

  <a class="chevron" href="#features" aria-label="Scroll to features">
    <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
      <path
        d="M5 9l7 7 7-7"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  </a>
</section>

<style>
  .hero {
    position: relative;
    min-height: 100svh;
    display: grid;
    place-items: center;
    background: radial-gradient(ellipse 90% 70% at 50% 30%, var(--void) 0%, oklch(0.09 0.004 75) 100%);
    padding: 64px 24px 96px;
  }

  .content {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 28px;
  }

  /* Staggered entrance — one orchestrated load, not scattered effects. */
  .wordmark,
  h1,
  .sub,
  .cta {
    animation: rise 900ms var(--ease-out-quint) both;
  }

  .wordmark {
    animation-delay: 0ms;
  }
  h1 {
    animation-delay: 120ms;
  }
  .sub {
    animation-delay: 240ms;
  }
  .cta {
    animation-delay: 1300ms; /* lands as the donut finishes sweeping */
  }

  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .wordmark {
    font-size: 15px;
    font-weight: 600;
    letter-spacing: 0.32em;
    text-transform: uppercase;
    color: var(--reclaim);
    margin-bottom: -8px;
  }

  h1 {
    font-size: clamp(40px, 7.2vw, 76px);
    font-weight: 200;
    letter-spacing: -0.03em;
    line-height: 1.06;
    color: var(--ink);
  }

  .sub {
    font-size: clamp(17px, 2.4vw, 21px);
    font-weight: 300;
    color: var(--ink2);
    max-width: 44ch;
  }

  .cta {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
  }

  .download {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 14px 28px;
    border-radius: 999px;
    background: var(--reclaim);
    color: oklch(0.16 0.02 58);
    font-size: 16px;
    font-weight: 600;
    text-decoration: none;
    box-shadow:
      0 0 0 1px oklch(1 0 0 / 0.08),
      0 8px 32px oklch(0.74 0.16 58 / 0.35);
    transition:
      background 150ms ease,
      transform var(--dur-1) var(--ease-out-quart),
      box-shadow 150ms ease;
  }

  @media (hover: hover) {
    .download:hover {
      background: var(--reclaim-bright);
      box-shadow:
        0 0 0 1px oklch(1 0 0 / 0.12),
        0 10px 40px oklch(0.74 0.16 58 / 0.5);
    }
  }

  .download:active {
    transform: scale(0.97);
  }

  .fine {
    font-size: 13px;
    color: var(--ink4);
  }

  .chevron {
    position: absolute;
    bottom: 28px;
    left: 50%;
    translate: -50% 0;
    color: var(--ink4);
    animation:
      rise 900ms var(--ease-out-quint) 2000ms both,
      bob 2.4s ease-in-out 3s infinite;
    transition: color 150ms ease;
  }

  @media (hover: hover) {
    .chevron:hover {
      color: var(--ink2);
    }
  }

  @keyframes bob {
    0%,
    100% {
      transform: translateY(0);
    }
    50% {
      transform: translateY(6px);
    }
  }
</style>
