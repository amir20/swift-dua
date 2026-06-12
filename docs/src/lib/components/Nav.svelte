<script lang="ts">
  import { onMount } from 'svelte';
  import { folderHue } from '$lib/palette';
  import { toggleTheme } from '$lib/theme';

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
  <button class="toggle" type="button" onclick={toggleTheme} aria-label="Toggle light or dark theme">
    <svg class="sun" viewBox="0 0 24 24" width="17" height="17" aria-hidden="true">
      <circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="2" />
      <path
        d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
    <svg class="moon" viewBox="0 0 24 24" width="17" height="17" aria-hidden="true">
      <path
        d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linejoin="round"
      />
    </svg>
  </button>
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
      background: var(--hover-bg);
    }
  }

  .toggle {
    display: inline-grid;
    place-items: center;
    width: 34px;
    height: 34px;
    padding: 0;
    border: 0;
    border-radius: 999px;
    background: transparent;
    color: var(--ink2);
    cursor: pointer;
    transition:
      color 150ms ease,
      background 150ms ease;
  }

  @media (hover: hover) {
    .toggle:hover {
      color: var(--ink);
      background: var(--hover-bg);
    }
  }

  /* The icon reflects the current theme via data-theme — no JS state. */
  .toggle .moon {
    display: none;
  }

  :global(:root[data-theme='light']) .toggle .sun {
    display: none;
  }

  :global(:root[data-theme='light']) .toggle .moon {
    display: block;
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
