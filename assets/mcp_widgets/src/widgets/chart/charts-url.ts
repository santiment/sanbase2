import type { ChartData } from "./contract";

const SANBASE_CHARTS_URL = "https://app.santiment.net/charts";

// TODO: We should form this link on backend, remove after update
export function buildChartsUrl(data: ChartData): string {
  if (data.series.length === 0) {
    return `${SANBASE_CHARTS_URL}?slug=${encodeURIComponent(data.slug)}`;
  }

  const settings = {
    slug: data.slug,
    from: data.period_start,
    to: data.period_end,
  };

  const widgets = [
    {
      widget: "ChartWidget",
      wm: data.series.map((s) => s.name),
      wax: data.series.map((s) => s.pane),
      wc: Object.fromEntries(data.series.map((s) => [s.name, s.color])),
    },
  ];

  const params = new URLSearchParams({
    settings: JSON.stringify(settings),
    widgets: JSON.stringify(widgets),
  });

  return `${SANBASE_CHARTS_URL}?${params.toString()}`;
}
