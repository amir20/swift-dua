<script lang="ts">
  import Nav from '$lib/components/Nav.svelte';
  import Hero from '$lib/components/Hero.svelte';
  import Features from '$lib/components/Features.svelte';
  import HowItWorks from '$lib/components/HowItWorks.svelte';
  import Footer from '$lib/components/Footer.svelte';

  const TITLE = 'Halo — See what’s eating your disk';
  const DESC =
    'A beautiful, blazing-fast disk-space visualizer for macOS. Scan any folder, explore the donut, reclaim space in one click. Free & open source.';
</script>

<svelte:head>
  <title>{TITLE}</title>
  <meta name="description" content={DESC} />
  <link rel="canonical" href="https://halodisk.app/" />

  <meta property="og:type" content="website" />
  <meta property="og:title" content={TITLE} />
  <meta property="og:description" content={DESC} />
  <meta property="og:url" content="https://halodisk.app/" />
  <meta property="og:image" content="https://halodisk.app/og.png" />

  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={TITLE} />
  <meta name="twitter:description" content={DESC} />
  <meta name="twitter:image" content="https://halodisk.app/og.png" />
</svelte:head>

<Nav />
<main>
  <Hero />
  <Features />
  <HowItWorks />
</main>
<Footer />
