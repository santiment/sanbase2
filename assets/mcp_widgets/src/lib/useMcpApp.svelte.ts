import { onMount } from "svelte";
import { App, type McpUiHostContext } from "@modelcontextprotocol/ext-apps";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { useUiCtx } from "san-webkit-next/ctx/ui";

export type McpAppOptions<T> = {
  name: string;
  parse: (result: CallToolResult) => T | null;
};

type McpAppState<T> = {
  data: T | null;
  loading: boolean;
  error: string | null;
  hostContext: McpUiHostContext | undefined;
};

export function useMcpApp<T>(opts: McpAppOptions<T>) {
  let instance: App | null = null;

  const state = $state<McpAppState<T>>({
    data: null,
    loading: true,
    error: null,
    hostContext: undefined,
  });

  const isNightMode = $derived(state.hostContext?.theme !== "light");

  const { ui } = useUiCtx.set({ isNightMode });

  $effect(() => {
    document.body.classList.toggle("night-mode", isNightMode);
    ui.$$.isNightMode = isNightMode;
  });

  onMount(async () => {
    const app = new App(
      { name: opts.name, version: "1.0.0" },
      { availableDisplayModes: ["inline"] },
    );

    app.ontoolresult = (result) => {
      try {
        const parsed = opts.parse(result);
        if (parsed === null) return;

        state.data = parsed;
        state.error = null;
      } catch (e) {
        console.error(e);
        state.error = e instanceof Error ? e.message : String(e);
      } finally {
        state.loading = false;
      }
    };

    app.onerror = (e) => {
      console.error(e);
      state.error = e instanceof Error ? e.message : String(e);
    };

    app.onhostcontextchanged = (params) => {
      state.hostContext = { ...state.hostContext, ...params };
    };

    try {
      await app.connect();

      instance = app;
      state.hostContext = app.getHostContext();
    } catch (e) {
      state.error = e instanceof Error ? e.message : String(e);
      state.loading = false;
    }
  });

  async function openLink(url: string): Promise<boolean> {
    if (!instance) return false;

    const u = new URL(url);

    u.searchParams.set("utm_source", "mcp_host");
    u.searchParams.set("utm_medium", "mcp_widget");
    u.searchParams.set("utm_campaign", opts.name);

    const tagged = u.toString();

    try {
      const { isError } = await instance.openLink({ url: tagged });
      if (isError) console.warn("openLink denied by host:", tagged);

      return !isError;
    } catch (e) {
      console.error(e);

      return false;
    }
  }

  return {
    mcpApp: {
      get $() {
        return state;
      },

      get isNightMode$() {
        return isNightMode;
      },

      openLink,
    },
  };
}
