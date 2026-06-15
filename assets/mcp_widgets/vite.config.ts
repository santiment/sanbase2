import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { viteSingleFile } from "vite-plugin-singlefile";
import { resolve } from "path";

const lib = (file: string) => resolve(__dirname, "lib", file);

const widget = process.env.WIDGET;

const buildConfig =
  widget !== undefined
    ? {
        outDir: resolve(__dirname, "../../priv/mcp_widgets"),
        emptyOutDir: false,
        rollupOptions: {
          input: resolve(__dirname, `src/${widget}.html`),
        },
      }
    : {};

export default defineConfig({
  plugins: [
    svelte({ configFile: resolve(__dirname, "svelte.config.js") }),
    viteSingleFile(),
  ],

  root: resolve(__dirname, "src"),
  publicDir: resolve(__dirname, "static"),

  resolve: {
    alias: [
      {
        find: /^\$app\/(state|navigation)$/,
        replacement: lib("sveltekit-noop.ts"),
      },
      { find: "$app/stores", replacement: lib("sveltekit-stores.ts") },
      { find: "@sentry/sveltekit", replacement: lib("sveltekit-noop.ts") },
    ],
  },

  // Widgets run in an MCP sandbox with CSP `connect-src 'none'` and receive
  // all data via JSON-RPC `tool-result` - they never call the backend directly.
  // These are shims for `san-webkit-next` transitive code (executor, auth, ws,
  // sentry, …) that references `process.env.*` at module init. Empty strings
  // make any accidental network call fail loud instead of silently hitting
  // api-stage; the booleans gate dev-only branches off.
  define: {
    "process.env.BACKEND_URL": JSON.stringify(""),
    "process.env.GQL_SERVER_URL": JSON.stringify(""),
    "process.env.IS_DEV_MODE": false,
    "process.env.IS_PROD_MODE": true,
  },

  build: buildConfig,
});
