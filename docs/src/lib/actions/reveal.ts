/**
 * Scroll-reveal Svelte action. Adds the hidden state only when JS runs
 * (no-JS visitors see everything), then flips to shown the first time the
 * element enters the viewport. `delay` staggers children.
 */
export function reveal(node: HTMLElement, opts: { delay?: number } = {}) {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  node.style.setProperty('--reveal-delay', `${opts.delay ?? 0}ms`);
  node.classList.add('reveal-armed');

  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          node.classList.add('reveal-shown');
          io.disconnect();
        }
      }
    },
    { threshold: 0.15, rootMargin: '0px 0px -10% 0px' }
  );
  io.observe(node);

  return {
    destroy() {
      io.disconnect();
    }
  };
}
