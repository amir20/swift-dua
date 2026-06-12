<script lang="ts">
  import { reveal } from '$lib/actions/reveal';

  const BEATS = [
    {
      n: '01',
      title: 'Scan streams in live',
      body: 'Pick a folder and watch the donut fill as the parallel scan completes each subtree — no waiting for the whole walk.'
    },
    {
      n: '02',
      title: 'Hover to explore',
      body: 'Every arc is the folder or file type under your cursor. Click to drill in; the breakdown sidebar follows.'
    },
    {
      n: '03',
      title: 'Reclaim with one click',
      body: 'Regenerable space is highlighted. Reclaim moves it to the Trash and the donut re-stitches instantly.'
    }
  ];
</script>

<section class="how" id="how">
  <div class="wrap">
    <p class="label" use:reveal>How it works</p>
    <h2 use:reveal={{ delay: 80 }}>Scan. Hover. Reclaim.</h2>

    <div class="stage">
      <!-- The screenshot straightens from a 3D tilt as it scrolls through view.
           Two themed mocks are swapped by data-theme (CSS below); replace each
           with a real capture (screenshot-{dark,light}.webp + png) when
           available. -->
      <div class="frame-tilt">
        <figure class="frame glass">
          <div class="titlebar" aria-hidden="true">
            <span class="light red"></span>
            <span class="light yellow"></span>
            <span class="light green"></span>
          </div>
          <img class="shot shot-dark" src="/screenshot-dark.svg" alt="Halo scanning a home folder, showing the usage donut and breakdown sidebar" loading="lazy" />
          <img class="shot shot-light" src="/screenshot-light.svg" alt="Halo scanning a home folder, showing the usage donut and breakdown sidebar" loading="lazy" />
        </figure>
      </div>

      <ol class="beats">
        {#each BEATS as beat, i}
          <li use:reveal={{ delay: i * 120 }}>
            <span class="n">{beat.n}</span>
            <div>
              <h3>{beat.title}</h3>
              <p>{beat.body}</p>
            </div>
          </li>
        {/each}
      </ol>
    </div>
  </div>
</section>

<style>
  .how {
    background: linear-gradient(var(--bg), var(--void));
    padding: 140px 0 160px;
    overflow: clip;
  }

  h2 {
    font-size: clamp(30px, 4.6vw, 48px);
    font-weight: 200;
    letter-spacing: -0.02em;
    color: var(--ink);
    margin: 12px 0 56px;
  }

  .stage {
    display: grid;
    grid-template-columns: 1.5fr 1fr;
    gap: 56px;
    align-items: center;
    perspective: 1400px;
  }

  @media (max-width: 880px) {
    .stage {
      grid-template-columns: 1fr;
    }
  }

  .frame-tilt {
    transform-style: preserve-3d;
  }

  /* Scroll-driven straighten where supported… */
  @supports (animation-timeline: view()) {
    .frame-tilt {
      animation: straighten linear both;
      animation-timeline: view();
      animation-range: entry 0% cover 55%;
    }
  }

  /* …and a one-shot settle for everyone else. */
  @supports not (animation-timeline: view()) {
    .frame-tilt {
      animation: settle 1200ms var(--ease-out-quint) both;
    }
  }

  @keyframes straighten {
    from {
      transform: rotateX(14deg) rotateY(-6deg) scale(0.92);
      opacity: 0.4;
    }
    to {
      transform: rotateX(0) rotateY(0) scale(1);
      opacity: 1;
    }
  }

  @keyframes settle {
    from {
      transform: rotateX(10deg) scale(0.95);
      opacity: 0;
    }
    to {
      transform: none;
      opacity: 1;
    }
  }

  .frame {
    border-radius: 16px;
    overflow: hidden;
    margin: 0;
  }

  .titlebar {
    display: flex;
    gap: 8px;
    padding: 12px 14px;
    border-bottom: 1px solid var(--glass-line);
  }

  .light {
    width: 12px;
    height: 12px;
    border-radius: 50%;
  }

  .red {
    background: oklch(0.66 0.18 25);
  }
  .yellow {
    background: oklch(0.8 0.15 85);
  }
  .green {
    background: oklch(0.72 0.17 145);
  }

  .frame img {
    display: block;
    width: 100%;
    height: auto;
  }

  /* Show the mock matching the active theme. */
  .frame .shot-light {
    display: none;
  }

  :global(:root[data-theme='light']) .frame .shot-dark {
    display: none;
  }

  :global(:root[data-theme='light']) .frame .shot-light {
    display: block;
  }

  .beats {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 32px;
  }

  .beats li {
    display: flex;
    gap: 18px;
    align-items: baseline;
  }

  .n {
    font-size: 14px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--reclaim);
    letter-spacing: 0.06em;
  }

  .beats h3 {
    font-size: 18px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--ink);
    margin-bottom: 6px;
  }

  .beats p {
    font-size: 15px;
    font-weight: 300;
    line-height: 1.55;
    color: var(--ink2);
  }
</style>
