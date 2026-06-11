import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({
      // Output a fully static site; GitHub Pages serves the artifact as-is.
      fallback: undefined,
      strict: true
    })
  }
};

export default config;
