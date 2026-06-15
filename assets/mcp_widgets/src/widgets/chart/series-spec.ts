import type { UTCTimestamp } from "@santiment-network/chart-next";

import {
  MetricStyle,
  MetricType,
  type TChartAssetMetric,
  type TMetricStyles,
} from "san-webkit-next/ctx/metrics-registry/types";
import type { TAssetSlug } from "san-webkit-next/ctx/assets";

import type {
  CandlePoint,
  ChartSeries,
  SeriesStyle,
  ValuePoint,
} from "./contract";

const STYLE_MAP: Record<SeriesStyle, TMetricStyles> = {
  candles: MetricStyle.CANDLES,
  line: MetricStyle.LINE,
  area: MetricStyle.AREA,
  histogram: MetricStyle.HISTOGRAM,
};

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
    style: STYLE_MAP[series.style] ?? MetricStyle.LINE,
    pane: 0,
    scaleId: `right-${series.id}`,
    color: series.color,
    unit: series.unit,
    selector: { slug: slug as TAssetSlug },
  };
}
