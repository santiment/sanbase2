import { MOCK_DATA as TRENDING_MOCK } from "../widgets/social-trends/mock";
import { CHART_MOCK } from "../widgets/chart/mock";

export type WidgetConfig = {
  label: string;
  url: string;
  mock: unknown;
  args: Record<string, unknown>;
};

export const WIDGETS: Record<string, WidgetConfig> = {
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
    args: {
      slug: "bitcoin",
      primary: "price",
      overlay: "social_volume_total",
      range: "7d",
    },
  },
};
