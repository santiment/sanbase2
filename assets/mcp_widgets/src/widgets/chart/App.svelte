<script lang="ts">
  import {
    capitalize,
    DEFAULT_FORMATTER,
    percentFormatter,
    usdFormatter,
  } from "san-webkit-next/utils/formatters";
  import { formatPercentChange } from "san-webkit-next/ui/app/Change";

  import ChartView from "./ChartView.svelte";
  import Change from "../../lib/Change.svelte";
  import WidgetShell from "../../lib/WidgetShell.svelte";
  import { useMcpApp } from "../../lib/useMcpApp.svelte";
  import { parseChartData, type Unit } from "./contract";
  import { buildChartsUrl } from "./charts-url";

  const { mcpApp } = useMcpApp({
    name: "santiment-chart",
    parse: parseChartData,
  });

  const title = $derived(
    mcpApp.$.data ? `📊 ${capitalize(mcpApp.$.data.slug)}` : "",
  );

  const formatterFor = (unit: Unit) =>
    unit === "usd"
      ? usdFormatter
      : unit === "percent"
        ? percentFormatter
        : DEFAULT_FORMATTER;
</script>

<WidgetShell
  {title}
  badge={mcpApp.$.data?.range}
  loading={mcpApp.$.loading}
  error={mcpApp.$.error}
  empty={!mcpApp.$.data || mcpApp.$.data.series.length === 0}
>
  {#snippet loadingSkeleton()}
    <div class="flex items-center gap-4 mb-3 flex-wrap">
      <div class="flex items-center gap-2">
        <div class="skeleton h-8 w-32"></div>
        <div class="skeleton h-5 w-16"></div>
        <div class="skeleton h-4 w-10"></div>
      </div>
      <div class="flex items-center gap-2 ml-auto">
        <div class="skeleton h-4 w-20"></div>
        <div class="skeleton h-5 w-16"></div>
        <div class="skeleton h-4 w-12"></div>
      </div>
    </div>
    <div class="skeleton w-full h-[400px]"></div>
  {/snippet}

  {#snippet summary()}
    {#if mcpApp.$.data}
      {@const sp = mcpApp.$.data.summary.primary}
      {@const so = mcpApp.$.data.summary.overlay}

      <div class="flex items-center gap-4 mb-3 flex-wrap">
        {#if sp}
          <div class="flex items-center gap-2">
            <span class="text-2xl font-semibold text-rhino">
              {formatterFor(sp.unit)(sp.current)}
            </span>

            <Change
              change={formatPercentChange(sp.change_pct)}
              class="text-sm font-medium"
            />

            <span class="text-sm text-waterloo">{mcpApp.$.data.range}</span>
          </div>
        {/if}

        {#if so}
          <div class="flex items-center gap-2 ml-auto">
            <span class="text-xs text-waterloo">{so.label}:</span>

            <span class="text-sm font-medium text-rhino">
              {formatterFor(so.unit)(so.current)}
            </span>

            <Change
              change={formatPercentChange(so.change_pct)}
              class="text-xs font-medium"
            />
          </div>
        {/if}
      </div>
    {/if}
  {/snippet}

  {#if mcpApp.$.data}
    {@const so = mcpApp.$.data.summary.overlay}

    {#key `${mcpApp.$.data.slug}|${mcpApp.$.data.range}|${so?.label ?? ""}`}
      <ChartView data={mcpApp.$.data} />
    {/key}
  {/if}

  {#snippet footer()}
    {#if mcpApp.$.data}
      <div class="mt-3 flex justify-end">
        <button
          type="button"
          onclick={() => mcpApp.openLink(buildChartsUrl(mcpApp.$.data!))}
          class="text-xs font-medium text-green hover:underline focus-visible:outline-2 focus-visible:outline-green focus-visible:outline-offset-2 rounded"
        >
          Open on Santiment Charts →
        </button>
      </div>
    {/if}
  {/snippet}
</WidgetShell>
