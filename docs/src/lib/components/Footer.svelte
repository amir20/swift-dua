<script lang="ts">
  import { reveal } from '$lib/actions/reveal';

  const FAQ = [
    {
      q: 'What does it need?',
      a: 'macOS 26 or later on Apple Silicon. One small download, no installer.'
    },
    {
      q: 'Is reclaiming safe?',
      a: 'Yes — Halo only moves items to the Trash. Nothing is deleted until you empty it.'
    },
    {
      q: 'How do updates work?',
      a: 'Halo updates itself via Sparkle, signed and notarized. No account, no nagging.'
    }
  ];
</script>

<footer class="footer">
  <div class="wrap">
    <div class="faq">
      {#each FAQ as item, i}
        <div class="qa" use:reveal={{ delay: i * 100 }}>
          <h3>{item.q}</h3>
          <p>{item.a}</p>
        </div>
      {/each}
    </div>

    <div class="base">
      <p class="made">
        Made by <a href="https://github.com/amir20" target="_blank" rel="noopener">Amir Raminfar</a>
        · <a href="https://github.com/amir20/Halo.app" target="_blank" rel="noopener">Source on GitHub</a>
        · <a href="/changelog">Changelog</a>
      </p>
      <p class="copy">© {new Date().getFullYear()} halodisk.app</p>
    </div>

    <p class="legal">
      macOS, Mac, and Apple Silicon are trademarks of Apple Inc. Halo is an independent project, not
      affiliated with or endorsed by Apple. No telemetry — your scans never leave your Mac.
    </p>
  </div>
</footer>

<style>
  .footer {
    background: var(--void);
    padding: 96px 0 48px;
    border-top: 1px solid var(--hairline);
  }

  .faq {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 36px;
    margin-bottom: 80px;
  }

  .qa h3 {
    font-size: 16px;
    font-weight: 600;
    color: var(--ink);
    margin-bottom: 8px;
  }

  .qa p {
    font-size: 14px;
    font-weight: 300;
    line-height: 1.6;
    color: var(--ink3);
  }

  .base {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 16px;
    flex-wrap: wrap;
  }

  .made {
    font-size: 14px;
    color: var(--ink3);
  }

  .made a {
    color: var(--ink2);
    text-decoration: none;
    border-bottom: 1px solid var(--hairline-strong);
    transition: color 150ms ease, border-color 150ms ease;
  }

  @media (hover: hover) {
    .made a:hover {
      color: var(--ink);
      border-color: var(--reclaim);
    }
  }

  .copy {
    font-size: 13px;
    color: var(--ink4);
  }

  .legal {
    margin-top: 20px;
    max-width: 70ch;
    font-size: 12px;
    line-height: 1.6;
    color: var(--ink4);
  }
</style>
