import type { UTCTimestamp } from "@santiment-network/chart-next";

import {
  MetricType,
  type TChartAssetMetric,
} from "san-webkit-next/ctx/metrics-registry/types";
import type { TAssetSlug } from "san-webkit-next/ctx/assets";

import type { CandlePoint, ChartSeries, ValuePoint } from "./contract";

const isCandle = (p: CandlePoint | ValuePoint): p is CandlePoint => "open" in p;

function toMetricData(series: ChartSeries) {
  return series.data.map((p) =>
    isCandle(p)
      ? {
          time: p.time as UTCTimestamp,
          value: p.close,
          open: p.open,
          high: p.high,
          low: p.low,
          close: p.close,
        }
      : { time: p.time as UTCTimestamp, value: p.value ?? undefined },
  );
}

export function toMetricConfig(
  series: ChartSeries,
  slug: string,
): TChartAssetMetric {
  return {
    type: MetricType.ASSET,
    apiMetricName: series.name,
    label: series.label,
    data: toMetricData(series),
    style: series.style,
    pane: 0,
    scaleId: `right-${series.id}`,
    color: series.color,
    unit: series.unit,
    selector: { slug: slug as TAssetSlug },
  };
}
