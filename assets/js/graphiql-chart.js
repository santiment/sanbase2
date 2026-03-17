/**
 * GraphiQL Chart Visualization.
 * Detects timeseries data in GraphQL responses and renders interactive charts.
 */
import { createChart, ColorType, CrosshairMode, LineSeries } from "lightweight-charts";

// ─── Timeseries detection ───────────────────────────────────────

/**
 * Walk a parsed GraphQL response and extract all timeseries data series.
 * Returns an array of { label, data: [{time, value}] } objects.
 *
 * Handles:
 *  - timeseriesDataJson / timeseriesDataPerSlugJson (JSON strings)
 *  - timeseriesData (array of {datetime, value} objects)
 *  - Any alias — detection is shape-based, not name-based
 */
export function extractTimeseries(responseJson) {
  const series = [];
  try {
    const parsed = typeof responseJson === "string" ? JSON.parse(responseJson) : responseJson;
    if (parsed && parsed.data) {
      walkNode(parsed.data, [], series);
    }
  } catch (e) {
    // not valid JSON
  }
  return series;
}

function walkNode(node, path, series) {
  if (node === null || node === undefined) return;

  // Case 1: JSON string that parses to timeseries data
  if (typeof node === "string") {
    tryParseJsonString(node, path, series);
    return;
  }

  // Case 2: Array — check for various timeseries shapes
  if (Array.isArray(node) && node.length > 0) {
    // 2a: [{datetime, value}, ...] — simple timeseries
    if (isDatetimeValueArray(node)) {
      series.push({
        label: pathToLabel(path),
        data: node.map(function (p) {
          return { time: toUnix(p.datetime), value: Number(p.value) };
        }).filter(function (p) { return !isNaN(p.time) && !isNaN(p.value); }),
      });
      return;
    }
    // 2b: [{datetime, data: [{slug, value}, ...]}, ...] — per-slug timeseries
    // Pivot into one series per slug
    if (isPerSlugArray(node)) {
      const bySlug = {};
      for (const point of node) {
        const t = toUnix(point.datetime);
        for (const entry of point.data) {
          const slug = entry.slug;
          if (!bySlug[slug]) bySlug[slug] = [];
          const v = Number(entry.value);
          if (!isNaN(t) && !isNaN(v)) bySlug[slug].push({ time: t, value: v });
        }
      }
      for (const slug of Object.keys(bySlug)) {
        series.push({ label: slug, data: bySlug[slug] });
      }
      return;
    }
    // Walk array elements
    for (let i = 0; i < node.length; i++) {
      walkNode(node[i], path, series);
    }
    return;
  }

  // Case 3: Object — recurse into each key
  if (typeof node === "object") {
    for (const key of Object.keys(node)) {
      walkNode(node[key], path.concat(key), series);
    }
  }
}

function tryParseJsonString(str, path, series) {
  let parsed;
  try {
    parsed = JSON.parse(str);
  } catch (e) {
    return;
  }

  // timeseriesDataJson: [[datetime, value], ...]
  if (Array.isArray(parsed) && parsed.length > 0) {
    if (isTwoElementArrayOfPairs(parsed)) {
      series.push({
        label: pathToLabel(path),
        data: parsed.map(function (p) {
          return { time: toUnix(p[0]), value: Number(p[1]) };
        }).filter(function (p) { return !isNaN(p.time) && !isNaN(p.value); }),
      });
      return;
    }
    // Array of {datetime, value} objects (some endpoints return this as JSON string)
    if (isDatetimeValueArray(parsed)) {
      series.push({
        label: pathToLabel(path),
        data: parsed.map(function (p) {
          return { time: toUnix(p.datetime), value: Number(p.value) };
        }).filter(function (p) { return !isNaN(p.time) && !isNaN(p.value); }),
      });
      return;
    }
    // Array of {datetime, data: [{slug, value}, ...]} — per-slug as JSON string
    if (isPerSlugArray(parsed)) {
      const bySlug = {};
      for (const point of parsed) {
        const t = toUnix(point.datetime);
        for (const entry of point.data) {
          const slug = entry.slug;
          if (!bySlug[slug]) bySlug[slug] = [];
          const v = Number(entry.value);
          if (!isNaN(t) && !isNaN(v)) bySlug[slug].push({ time: t, value: v });
        }
      }
      for (const slug of Object.keys(bySlug)) {
        series.push({ label: slug, data: bySlug[slug] });
      }
      return;
    }
  }

  // timeseriesDataPerSlugJson: { slug: [[datetime, value], ...], ... }
  if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
    for (const key of Object.keys(parsed)) {
      const val = parsed[key];
      if (Array.isArray(val) && val.length > 0 && isTwoElementArrayOfPairs(val)) {
        series.push({
          label: key,
          data: val.map(function (p) {
            return { time: toUnix(p[0]), value: Number(p[1]) };
          }).filter(function (p) { return !isNaN(p.time) && !isNaN(p.value); }),
        });
      }
    }
  }
}

function isDatetimeValueArray(arr) {
  if (arr.length === 0) return false;
  const first = arr[0];
  return first && typeof first === "object" && "datetime" in first && "value" in first;
}

function isPerSlugArray(arr) {
  if (arr.length === 0) return false;
  const first = arr[0];
  return first && typeof first === "object" &&
    "datetime" in first &&
    "data" in first &&
    Array.isArray(first.data) &&
    first.data.length > 0 &&
    "slug" in first.data[0] &&
    "value" in first.data[0];
}

function isTwoElementArrayOfPairs(arr) {
  if (arr.length === 0) return false;
  const first = arr[0];
  return Array.isArray(first) && first.length === 2 && typeof first[0] === "string";
}

function toUnix(datetimeStr) {
  return Math.floor(new Date(datetimeStr).getTime() / 1000);
}

function pathToLabel(path) {
  // Skip generic keys to make labels cleaner
  const skip = new Set(["getMetric", "data"]);
  const parts = path.filter(function (p) { return !skip.has(p); });
  return parts.length > 0 ? parts.join(" → ") : "value";
}

// ─── Chart rendering ────────────────────────────────────────────

const COLORS = [
  "#2962FF", "#FF6D00", "#2E7D32", "#AA00FF",
  "#D50000", "#00BFA5", "#FFD600", "#C51162",
];

/**
 * Render a lightweight-charts instance into a container element.
 * Returns a cleanup function.
 */
export function renderChart(container, seriesList, isDark) {
  const bgColor = isDark ? "#1e1e1e" : "#ffffff";
  const textColor = isDark ? "#d4d4d4" : "#333333";
  const gridColor = isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.06)";

  const chart = createChart(container, {
    width: container.clientWidth,
    height: container.clientHeight,
    layout: {
      background: { type: ColorType.Solid, color: bgColor },
      textColor: textColor,
      fontFamily: "system-ui, -apple-system, sans-serif",
      fontSize: 12,
    },
    grid: {
      vertLines: { color: gridColor },
      horzLines: { color: gridColor },
    },
    crosshair: {
      mode: CrosshairMode.Normal,
    },
    timeScale: {
      timeVisible: true,
      secondsVisible: false,
      borderColor: gridColor,
    },
    rightPriceScale: {
      borderColor: gridColor,
    },
  });

  seriesList.forEach(function (s, i) {
    const color = COLORS[i % COLORS.length];
    const line = chart.addSeries(LineSeries, {
      color: color,
      lineWidth: 2,
      title: s.label,
      crosshairMarkerRadius: 4,
    });
    line.setData(s.data);
  });

  chart.timeScale().fitContent();

  // Resize observer
  const ro = new ResizeObserver(function () {
    chart.applyOptions({
      width: container.clientWidth,
      height: container.clientHeight,
    });
  });
  ro.observe(container);

  return function cleanup() {
    ro.disconnect();
    chart.remove();
  };
}
