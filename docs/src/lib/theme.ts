/**
 * Theme toggle. The current theme lives on `<html data-theme>`, set before
 * first paint by the inline script in app.html; the CSS in app.css keys off it.
 * This just flips that attribute, persists the explicit choice, and keeps the
 * theme-color meta in sync. The toggle button's icon is driven purely by the
 * data-theme attribute in CSS, so there's no reactive state to hydrate.
 */
export function toggleTheme(): void {
  const root = document.documentElement;
  const next = root.dataset.theme === 'light' ? 'dark' : 'light';
  root.dataset.theme = next;
  try {
    localStorage.setItem('theme', next);
  } catch {
    /* private mode / storage disabled — the choice just won't persist */
  }
  document
    .querySelector('meta[name="theme-color"]')
    ?.setAttribute('content', next === 'light' ? '#ffffff' : '#0c0c0b');
}
