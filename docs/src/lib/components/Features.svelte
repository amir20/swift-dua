<script lang="ts">
  import GlassCard from './GlassCard.svelte';
  import { reveal } from '$lib/actions/reveal';
  import { folderHue } from '$lib/palette';
</script>

<section class="features" id="features">
  <!-- Drifting color blobs in the app's folder hues, behind the glass. -->
  <div class="blobs" aria-hidden="true">
    <div class="blob b1" style:background={folderHue(0)}></div>
    <div class="blob b2" style:background={folderHue(1)}></div>
    <div class="blob b3" style:background={folderHue(2)}></div>
    <div class="blob b4" style:background={folderHue(4)}></div>
  </div>

  <div class="wrap">
    <p class="label" use:reveal>Why Halo</p>
    <h2 use:reveal={{ delay: 80 }}>Your whole disk, one glance.</h2>

    <div class="grid">
      <div use:reveal={{ delay: 0 }}>
        <GlassCard title="Blazing fast" accent="oklch(0.74 0.16 58)">
          {#snippet icon()}
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M13 2 4.5 13.5H11L9.5 22 19 10h-6.5L13 2z" fill="currentColor"/></svg>
          {/snippet}
          A fully parallel scanner walks every folder at once over one shared work
          queue — results stream into the donut live, in seconds.
        </GlassCard>
      </div>

      <div use:reveal={{ delay: 80 }}>
        <GlassCard title="Two lenses" accent="oklch(0.7 0.17 256)">
          {#snippet icon()}
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3a9 9 0 0 1 9 9h-9V3z" fill="currentColor"/></svg>
          {/snippet}
          Flip between <em>by folder</em> and <em>by type</em> — the donut and
          breakdown sidebar stay perfectly in sync as you drill in.
        </GlassCard>
      </div>

      <div use:reveal={{ delay: 160 }}>
        <GlassCard title="Reclaim space" accent={folderHue(1)}>
          {#snippet icon()}
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M12 3v10m0 0 4-4m-4 4-4-4M4 17c2.5 2.7 13.5 2.7 16 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
          {/snippet}
          Halo spots regenerable space — caches, node_modules, DerivedData — and
          reclaims it in one click, safely into the Trash.
        </GlassCard>
      </div>

      <div use:reveal={{ delay: 240 }}>
        <GlassCard title="Native &amp; private" accent={folderHue(5)}>
          {#snippet icon()}
            <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M12 2 4 6v6c0 5 3.5 8.5 8 10 4.5-1.5 8-5 8-10V6l-8-4z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>
          {/snippet}
          Pure SwiftUI, built for macOS 26. No telemetry, no accounts — your scan
          never leaves your Mac.
        </GlassCard>
      </div>
    </div>
  </div>
</section>

<style>
  .features {
    position: relative;
    background: var(--bg);
    padding: 140px 0;
    overflow: clip;
  }

  .blobs {
    position: absolute;
    inset: 0;
    filter: blur(110px);
    opacity: 0.16;
    pointer-events: none;
  }

  .blob {
    position: absolute;
    width: 480px;
    height: 480px;
    border-radius: 50%;
  }

  .b1 {
    top: -10%;
    left: -8%;
    animation: drift1 26s ease-in-out infinite alternate;
  }
  .b2 {
    top: 30%;
    right: -12%;
    animation: drift2 32s ease-in-out infinite alternate;
  }
  .b3 {
    bottom: -15%;
    left: 22%;
    animation: drift1 38s ease-in-out infinite alternate-reverse;
  }
  .b4 {
    top: 5%;
    left: 45%;
    width: 360px;
    height: 360px;
    animation: drift2 29s ease-in-out infinite alternate-reverse;
  }

  @keyframes drift1 {
    to {
      transform: translate(120px, 80px) scale(1.15);
    }
  }

  @keyframes drift2 {
    to {
      transform: translate(-100px, -70px) scale(0.9);
    }
  }

  .wrap {
    position: relative;
  }

  h2 {
    font-size: clamp(30px, 4.6vw, 48px);
    font-weight: 200;
    letter-spacing: -0.02em;
    color: var(--ink);
    margin: 12px 0 48px;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 20px;
  }

  .grid > div {
    display: grid;
  }

  em {
    font-style: normal;
    color: var(--ink);
  }
</style>
