<script lang="ts">
  import Button from "san-webkit-next/ui/core/Button";
  import { MOCK_DATA as TRENDING_MOCK } from "../widgets/social-trends/mock";
  import { CHART_MOCK } from "../widgets/chart/mock";

  type WidgetConfig = {
    label: string;
    url: string;
    mock: unknown;
    args: object;
  };

  const WIDGETS: Record<string, WidgetConfig> = {
    "social-trends": {
      label: "Social Trends",
      url: "/social-trends.html",
      mock: TRENDING_MOCK,
      args: { time_period: "1h" },
    },
    chart: {
      label: "Chart",
      url: "/chart.html",
      mock: CHART_MOCK,
      args: { slug: "bitcoin", primary: "price", overlay: "social_volume_total", range: "7d" },
    },
  };

  let selected = $state<keyof typeof WIDGETS>("social-trends");
  let iframeEl = $state<HTMLIFrameElement>();
  let iframeHeight = $state(0);

  const current = $derived(WIDGETS[selected]);

  function postToWidget(method: string, params: object) {
    iframeEl?.contentWindow?.postMessage({ jsonrpc: "2.0", method, params }, "*");
  }

  function deliverToolResult(data: unknown, args: object) {
    postToWidget("ui/notifications/tool-input", { arguments: args });
    postToWidget("ui/notifications/tool-result", {
      content: [{ type: "text", text: JSON.stringify(data) }],
      structuredContent: data,
      isError: false,
    });
  }

  window.addEventListener("message", (e) => {
    const msg = e.data;
    if (!msg || typeof msg !== "object") return;

    if (msg.method === "ui/initialize" && msg.id != null) {
      iframeEl?.contentWindow?.postMessage(
        {
          jsonrpc: "2.0",
          id: msg.id,
          result: {
            protocolVersion: "2026-01-26",
            hostCapabilities: {},
            hostInfo: { name: "san-mcp-apps-harness", version: "0.0.0" },
            hostContext: {},
          },
        },
        "*",
      );
    }

    if (msg.method === "ui/notifications/initialized") {
      deliverToolResult(current.mock, current.args);
    }

    if (msg.method === "ui/notifications/size-changed" && msg.params?.height) {
      iframeHeight = msg.params.height;
    }

    if (msg.method === "ui/message" && msg.id != null) {
      iframeEl?.contentWindow?.postMessage(
        { jsonrpc: "2.0", id: msg.id, result: {} },
        "*",
      );
      console.info("[harness] widget sent message:", msg.params);
    }
  });

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
      onclick={() => deliverToolResult(current.mock, current.args)}
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
        title="Widget preview"
        sandbox="allow-scripts allow-same-origin"
        class="w-full border-none block"
        style:height="{iframeHeight}px"
        style:visibility={iframeHeight ? "visible" : "hidden"}
      ></iframe>
    </div>
  </main>
</div>
