import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'
import { componentStyleSelector } from 'san-webkit-next/plugins/svelte.js'

/** @type {import("@sveltejs/vite-plugin-svelte").SvelteConfig} */
export default {
  preprocess: [vitePreprocess(), componentStyleSelector()],
}
