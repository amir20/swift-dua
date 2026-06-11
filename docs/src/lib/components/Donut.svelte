<script lang="ts">
  import { onMount } from 'svelte';
  import { folderHue } from '$lib/palette';

  // A plausible scan: one dominant folder, then a descending tail (fractions of 1).
  const FRACTIONS = [0.3, 0.17, 0.12, 0.09, 0.07, 0.06, 0.05, 0.04, 0.035, 0.03, 0.02, 0.015];

  const R = 150;
  const STROKE = 46;
  const C = 2 * Math.PI * R;
  const GAP = 4; // dash units between segments
  const SWEEP_MS = 1200;

  // Quartic ease-out over the *cumulative* sweep, so the ring draws fast and
  // settles gently — each segment animates linearly inside its own window.
  const easeOutQuart = (t: number) => 1 - Math.pow(1 - t, 4);

  const usable = C - FRACTIONS.length * GAP;
  let acc = 0;
  const segments = FRACTIONS.map((f, i) => {
    const len = f * usable;
    const startFrac = acc;
    acc += f;
    const t0 = SWEEP_MS * easeOutQuart(startFrac);
    const t1 = SWEEP_MS * easeOutQuart(acc);
    return {
      len,
      color: folderHue(i),
      angle: -90 + (startFrac * usable + i * GAP) * (360 / C),
      delay: t0,
      dur: Math.max(t1 - t0, 16)
    };
  });

  // Center label counts up like a finishing scan.
  const TOTAL_GB = 482;
  let shown = $state(0);
  let done = $state(false);

  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      shown = TOTAL_GB;
      done = true;
      return;
    }
    const start = performance.now();
    const DUR = 1400;
    let raf = 0;
    const tick = (now: number) => {
      const t = Math.min((now - start) / DUR, 1);
      shown = Math.round(TOTAL_GB * easeOutQuart(t));
      if (t < 1) raf = requestAnimationFrame(tick);
      else done = true;
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  });

  // Pointer parallax: the donut tilts a few degrees toward the cursor.
  let tiltX = $state(0);
  let tiltY = $state(0);

  function onPointerMove(e: PointerEvent) {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const nx = (e.clientX - rect.left) / rect.width - 0.5;
    const ny = (e.clientY - rect.top) / rect.height - 0.5;
    tiltX = -ny * 7;
    tiltY = nx * 7;
  }

  function onPointerLeave() {
    tiltX = 0;
    tiltY = 0;
  }
</script>

<div
  class="scene"
  onpointermove={onPointerMove}
  onpointerleave={onPointerLeave}
  role="img"
  aria-label="Donut chart visualizing disk usage by folder"
>
  <div class="halo" aria-hidden="true"></div>

  <div class="tilt" style:transform="rotateX({tiltX}deg) rotateY({tiltY}deg)">
    <svg viewBox="0 0 400 400" class="ring">
      <g class="spin">
        {#each segments as seg}
          <circle
            cx="200"
            cy="200"
            r={R}
            fill="none"
            stroke={seg.color}
            stroke-width={STROKE}
            stroke-linecap="butt"
            class="seg"
            style:--len="{seg.len}px"
            style:--rest="{C - seg.len}px"
            style:--circ="{C}px"
            style:animation-delay="{seg.delay}ms"
            style:animation-duration="{seg.dur}ms"
            transform="rotate({seg.angle} 200 200)"
          />
        {/each}
      </g>
    </svg>

    <div class="center" class:done>
      <div class="amount"><span class="num">{shown}</span><span class="unit">GB</span></div>
      <div class="volume">Macintosh HD</div>
    </div>
  </div>
</div>

<style>
  .scene {
    position: relative;
    width: min(440px, 86vw);
    aspect-ratio: 1;
    perspective: 900px;
  }

  .halo {
    position: absolute;
    inset: -22%;
    border-radius: 50%;
    background: radial-gradient(
      circle,
      oklch(0.74 0.16 58 / 0.16) 0%,
      oklch(0.7 0.17 256 / 0.1) 38%,
      transparent 68%
    );
    filter: blur(8px);
    animation:
      halo-in 1600ms var(--ease-out-quart) 400ms both,
      breathe 6s ease-in-out 2s infinite alternate;
    pointer-events: none;
  }

  @keyframes halo-in {
    from {
      opacity: 0;
      transform: scale(0.86);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes breathe {
    from {
      opacity: 0.75;
      transform: scale(0.985);
    }
    to {
      opacity: 1;
      transform: scale(1.025);
    }
  }

  .tilt {
    position: absolute;
    inset: 0;
    transform-style: preserve-3d;
    transition: transform 400ms var(--ease-out-quart);
    will-change: transform;
  }

  .ring {
    width: 100%;
    height: 100%;
    display: block;
  }

  /* Imperceptible idle rotation — alive, never distracting. */
  .spin {
    transform-origin: 200px 200px;
    animation: spin 360s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  /* Each arc sweeps in by growing its dash from zero — reads as a scan completing. */
  .seg {
    stroke-dasharray: var(--len) var(--rest);
    animation-name: sweep;
    animation-timing-function: linear;
    animation-fill-mode: both;
    transition: filter 150ms ease;
    pointer-events: visibleStroke;
  }

  .seg:hover {
    filter: brightness(1.18);
  }

  @keyframes sweep {
    from {
      stroke-dasharray: 0px var(--circ);
    }
    to {
      stroke-dasharray: var(--len) var(--rest);
    }
  }

  .center {
    position: absolute;
    inset: 0;
    display: grid;
    place-content: center;
    text-align: center;
    gap: 4px;
    pointer-events: none;
    transform: translateZ(40px);
  }

  .amount {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 6px;
  }

  .num {
    font-size: clamp(44px, 9vw, 64px);
    font-weight: 200;
    letter-spacing: -0.02em;
    font-variant-numeric: tabular-nums;
    color: var(--ink);
  }

  .unit {
    font-size: clamp(18px, 3.4vw, 24px);
    font-weight: 300;
    color: var(--ink3);
  }

  .volume {
    font-size: 14px;
    font-weight: 400;
    letter-spacing: 0.02em;
    color: var(--ink4);
    opacity: 0;
    transition: opacity 600ms var(--ease-out-quart);
  }

  .center.done .volume {
    opacity: 1;
  }
</style>
