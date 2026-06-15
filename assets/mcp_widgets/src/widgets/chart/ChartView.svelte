<script lang="ts">
  import Chart, { RawSeries, Tooltip } from "san-webkit-next/ui/app/Chart";
  import {
    useChartCtx,
    useChartGlobalParametersCtx,
    useChartPanesCtx,
    useMetricSeriesCtx,
  } from "san-webkit-next/ui/app/Chart/ctx";
  import { useUiCtx } from "san-webkit-next/ctx/ui";
  import { getFormattedDetailedTimestamp } from "san-webkit-next/utils/dates";
  import type { TInterval } from "san-webkit-next/ui/app/Chart/api";
  import type { TAssetSlug } from "san-webkit-next/ctx/assets";

  import type { ChartData } from "./contract";
  import { toMetricConfig } from "./series-spec";

  const timeFormatter = (time: number) =>
    getFormattedDetailedTimestamp(new Date(time * 1000), { utc: true });

  type TProps = {
    data: ChartData;
    isNightMode: boolean;
  };
  const { data, isNightMode }: TProps = $props();

  useUiCtx.set({ isNightMode });
  useChartCtx.set();
  useChartPanesCtx.set();
  useChartGlobalParametersCtx.set({
    from: data.period_start,
    to: data.period_end,
    interval: data.interval as TInterval,
    selector: { slug: data.slug as TAssetSlug },
    includeIncompleteData: false,
  });

  const { metricSeries } = useMetricSeriesCtx.set(
    data.series.map((s) => toMetricConfig(s, data.slug)),
  );
</script>

<div class="w-full h-[400px]">
  <Chart
    watermark
    class="h-full w-full"
    onRangeSelectChange={() => {}}
    onRangeSelectEnd={() => {}}
    options={{
      timeScale: { timeVisible: true, secondsVisible: false },
      localization: { timeFormatter },
    }}
  >
    {#snippet children()}
      {#each metricSeries.$ as series (series.id)}
        <RawSeries {series} />
      {/each}
      <Tooltip />
    {/snippet}
  </Chart>
</div>
