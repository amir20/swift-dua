<script lang="ts">
  import { onMount } from 'svelte';
  import { folderHue } from '$lib/palette';

  const DMG = 'https://github.com/amir20/Halo.app/releases/latest/download/Halo.dmg';

  // The pill stays hidden over the hero and fades in once it scrolls out.
  let visible = $state(false);

  onMount(() => {
    const sentinel = document.querySelector('#top');
    if (!sentinel) {
      visible = true;
      return;
    }
    const io = new IntersectionObserver(([entry]) => (visible = entry.intersectionRatio < 0.25), {
      threshold: [0, 0.25, 1]
    });
    io.observe(sentinel);
    return () => io.disconnect();
  });
</script>

<nav class="pill glass" class:visible aria-label="Site">
  <a class="brand" href="#top">
    <span class="dot" style:background={folderHue(0)}></span>
    Halo
  </a>
  <a href="#features">Features</a>
  <a href="#how">How it works</a>
  <a href="https://github.com/amir20/Halo.app" target="_blank" rel="noopener">GitHub</a>
  <a class="get" href={DMG}>Download</a>
</nav>

<style>
  .pill {
    position: fixed;
    top: 16px;
    left: 50%;
    z-index: 10;
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px;
    border-radius: 999px;
    opacity: 0;
    transform: translate(-50%, -12px);
    pointer-events: none;
    transition:
      opacity var(--dur-3) var(--ease-out-quart),
      transform var(--dur-3) var(--ease-out-quart);
  }

  .pill.visible {
    opacity: 1;
    transform: translate(-50%, 0);
    pointer-events: auto;
  }

  .pill a {
    padding: 8px 14px;
    border-radius: 999px;
    font-size: 14px;
    font-weight: 500;
    color: var(--ink2);
    text-decoration: none;
    transition:
      color 150ms ease,
      background 150ms ease;
    white-space: nowrap;
  }

  @media (hover: hover) {
    .pill a:hover {
      color: var(--ink);
      background: oklch(1 0 0 / 0.07);
    }
  }

  .brand {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-weight: 600;
    color: var(--ink) !important;
  }

  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    box-shadow: 0 0 12px oklch(0.72 0.125 35 / 0.8);
  }

  .get {
    background: var(--reclaim);
    color: oklch(0.16 0.02 58) !important;
    font-weight: 600;
  }

  @media (hover: hover) {
    .get:hover {
      background: var(--reclaim-bright) !important;
    }
  }

  @media (max-width: 560px) {
    .pill a:not(.brand):not(.get) {
      display: none;
    }
  }
</style>
