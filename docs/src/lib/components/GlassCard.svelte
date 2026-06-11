<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    title,
    accent,
    icon,
    children
  }: { title: string; accent: string; icon: Snippet; children: Snippet } = $props();
</script>

<div class="card glass">
  <div class="icon" style:color={accent} style:--accent={accent}>
    {@render icon()}
  </div>
  <h3>{title}</h3>
  <p>{@render children()}</p>
</div>

<style>
  .card {
    border-radius: var(--radius);
    padding: 28px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    transition: transform var(--dur-3) var(--ease-out-quart);
  }

  @media (hover: hover) {
    .card:hover {
      transform: translateY(-4px);
    }
  }

  .icon {
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border-radius: 12px;
    background: color-mix(in oklch, var(--accent) 14%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in oklch, var(--accent) 25%, transparent);
  }

  h3 {
    font-size: 19px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  p {
    font-size: 15px;
    font-weight: 300;
    line-height: 1.55;
    color: var(--ink2);
  }
</style>
