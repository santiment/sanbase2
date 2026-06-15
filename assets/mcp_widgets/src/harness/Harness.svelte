<script lang="ts">
  import {
    AppBridge,
    PostMessageTransport,
  } from "@modelcontextprotocol/ext-apps/app-bridge";
  import Button from "san-webkit-next/ui/core/Button";
  import { WIDGETS } from "./widgets";

  let selected = $state<keyof typeof WIDGETS>("social-trends");
  let iframeEl = $state<HTMLIFrameElement>();
  let iframeHeight = $state(0);
  let bridge: AppBridge | null = null;

  const current = $derived(WIDGETS[selected]);

  async function setupBridge() {
    if (!iframeEl?.contentWindow) return;

    await bridge?.close();

    bridge = new AppBridge(
      null,
      { name: "san-mcp-apps-harness", version: "0.0.0" },
      {},
    );

    bridge.oninitialized = () => deliverMock();

    bridge.onsizechange = ({ height }) => {
      if (height) iframeHeight = height;
    };

    bridge.onopenlink = async ({ url }) => {
      console.info("[harness] widget openLink:", url);
      return { isError: false };
    };

    bridge.onmessage = async (params) => {
      console.info("[harness] widget message:", params);
      return {};
    };

    const transport = new PostMessageTransport(
      iframeEl.contentWindow,
      iframeEl.contentWindow,
    );

    await bridge.connect(transport);
  }

  function deliverMock() {
    if (!bridge) return;

    bridge.sendToolInput({ arguments: current.args });
    bridge.sendToolResult({
      content: [{ type: "text", text: JSON.stringify(current.mock) }],
      structuredContent: current.mock as Record<string, unknown>,
      isError: false,
    });
  }

  function switchWidget(key: keyof typeof WIDGETS) {
    iframeHeight = 0;
    selected = key;
  }
</script>

<div class="night-mode flex h-screen bg-white overflow-hidden">
  <aside
    class="w-64 shrink-0 p-5 bg-athens border-r border-porcelain flex flex-col gap-3"
  >
    <h2 class="text-base font-semibold text-rhino">MCP App Harness</h2>
    <p class="text-xs text-waterloo leading-relaxed">
      Simulates Claude.ai host. Widget receives data via postMessage.
    </p>

    <label class="flex flex-col gap-1 text-xs text-waterloo">
      Widget
      <select
        bind:value={selected}
        onchange={() => switchWidget(selected)}
        class="px-2 py-1.5 bg-white border border-porcelain rounded text-xs text-rhino focus:outline-none focus:border-green"
      >
        {#each Object.entries(WIDGETS) as [key, config]}
          <option value={key}>{config.label}</option>
        {/each}
      </select>
    </label>

    <Button
      variant="fill"
      class="w-full justify-start focus:outline-none"
      onclick={deliverMock}
    >
      ↺ Resend mock data
    </Button>
  </aside>

  <main class="flex-1 flex items-center justify-center bg-athens overflow-auto">
    <div
      class="w-[700px] border border-porcelain rounded-lg overflow-hidden shadow-sm"
    >
      <iframe
        bind:this={iframeEl}
        src={current.url}
        onload={setupBridge}
        title="Widget preview"
        sandbox="allow-scripts allow-same-origin"
        class="w-full border-none block"
        style:height="{iframeHeight}px"
        style:visibility={iframeHeight ? "visible" : "hidden"}
      ></iframe>
    </div>
  </main>
</div>
