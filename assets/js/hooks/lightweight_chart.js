// Render an inline price/metric chart from a deep-research `chart` event, using
// lightweight-charts v5 (TradingView's open-source lib, already a dep).
//
// The element carries the render-ready payload in `data-chart` (JSON):
//   { slug, range, summary, series: [ { style, color, pane, data:[...] }, ... ] }
// Each series is fed to the chart unchanged — `style` picks the series type,
// `pane` the pane index, and `data` is `{time, open/high/low/close}` (candles)
// or `{time, value}` (line/area/histogram), with `time` a UNIX timestamp (s).
//
// The container is `phx-update="ignore"` so LiveView never patches the canvas the
// chart builds; this hook owns it. Theme tracks the page's `data-theme`.
import {
  createChart,
  CandlestickSeries,
  LineSeries,
  AreaSeries,
  HistogramSeries,
} from "lightweight-charts"

const SERIES_TYPE = {
  candles: CandlestickSeries,
  line: LineSeries,
  area: AreaSeries,
  histogram: HistogramSeries,
}

function palette() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark"
  return dark
    ? { bg: "#1d232a", text: "#a6adbb", grid: "#2a323c", border: "#2a323c" }
    : { bg: "#ffffff", text: "#4b5563", grid: "#eef0f2", border: "#e5e7eb" }
}

export const LightweightChart = {
  mounted() {
    this.render()
    // re-color when the admin theme toggle stamps <html data-theme>
    this.themeObserver = new MutationObserver(() => this.render())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })
  },
  updated() {
    // Chart data is terminal — only rebuild if the payload actually changed.
    if (this.el.dataset.chart !== this._raw) this.render()
  },
  destroyed() {
    if (this.themeObserver) this.themeObserver.disconnect()
    if (this.chart) {
      this.chart.remove()
      this.chart = null
    }
  },
  render() {
    this._raw = this.el.dataset.chart
    let spec
    try {
      spec = JSON.parse(this._raw)
    } catch (e) {
      console.error("[LightweightChart] could not parse data-chart", e)
      return
    }
    const series = Array.isArray(spec.series) ? spec.series : []
    const shape = series.map((s) => `${s.style}:${(s.data || []).length}pts`).join(", ")

    const canvas = this.el.querySelector(".dra-chart-canvas") || this.el
    if (this.chart) {
      this.chart.remove()
      this.chart = null
    }
    canvas.innerHTML = ""

    // Self-describing states so a blank box is never ambiguous: no series / no
    // data points → say so in the box, rather than render nothing.
    const totalPoints = series.reduce((n, s) => n + ((s.data && s.data.length) || 0), 0)
    if (!series.length || !totalPoints) {
      canvas.innerHTML = note(`No chart data returned${shape ? ` (${shape})` : ""}.`)
      return
    }

    try {
      const c = palette()
      const chart = createChart(canvas, {
        autoSize: true,
        // Fallback dimensions so the chart is never 0×0 if the container hasn't
        // been laid out yet (autoSize then takes over via ResizeObserver).
        width: canvas.clientWidth || 600,
        height: canvas.clientHeight || 288,
        layout: {
          background: { color: c.bg },
          textColor: c.text,
          attributionLogo: false,
        },
        grid: { vertLines: { color: c.grid }, horzLines: { color: c.grid } },
        rightPriceScale: { borderColor: c.border },
        timeScale: { borderColor: c.border, timeVisible: true, secondsVisible: false },
      })
      this.chart = chart

      for (const s of series) {
        const def = SERIES_TYPE[s.style] || LineSeries
        const pane = Number.isInteger(s.pane) ? s.pane : 0
        const opts = s.color && s.style !== "candles" ? { color: s.color } : {}
        const api = chart.addSeries(def, opts, pane)
        api.setData(Array.isArray(s.data) ? s.data : [])
      }
      chart.timeScale().fitContent()
    } catch (e) {
      console.error("[LightweightChart] render failed", e)
      canvas.innerHTML = note("Chart failed to render — see browser console.")
    }
  },
}

// A centered faint message shown inside the canvas box when there's no chart to draw.
function note(text) {
  const div = document.createElement("div")
  div.style.cssText =
    "display:flex;align-items:center;justify-content:center;height:100%;width:100%;" +
    "font-size:0.8rem;color:#9ca3af;text-align:center;padding:1rem;"
  div.textContent = text
  return div.outerHTML
}
