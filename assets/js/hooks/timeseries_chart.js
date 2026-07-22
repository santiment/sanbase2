/**
 * TimeseriesChart — reusable Grafana-style multi-series time chart for the
 * admin panel. Server-side counterpart: SanbaseWeb.Admin.TimeseriesChart —
 * render `<.timeseries_chart id="..." />` and push data with
 * `TimeseriesChart.push_data(socket, id, series, value_kind: :bytes)`.
 *
 * The LiveView pushes `chart-data-<element id>` events with
 * `{series: [{name, points: [[unixSeconds, value], ...]}], value_kind}`
 * where value_kind is "bytes" | "count" | "percent".
 * One hook instance owns one lightweight-charts instance plus an HTML
 * legend row; it re-renders on new data and re-colors on theme toggle.
 *
 * Colors: validated categorical palette (8 slots, fixed order — see the
 * dataviz palette reference). A series keeps its slot for the lifetime of
 * the page even when other series come and go; at most 8 series are drawn,
 * the legend notes any overflow.
 */
import { createChart, ColorType, CrosshairMode, LineSeries } from "lightweight-charts"

const PALETTE = {
  // validated against surface #ffffff (adjacent pairs, CVD ΔE ≥ 8)
  light: ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"],
  // validated against surface #1d232a
  dark: ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"],
}

const CHROME = {
  light: { text: "#898781", grid: "#e1e0d9" },
  dark: { text: "#898781", grid: "#2c2c2a" },
}

const MAX_SERIES = 8

function themeMode() {
  return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light"
}

function fmtBytes(value) {
  const abs = Math.abs(value)
  if (abs >= 1073741824) return (value / 1073741824).toFixed(2) + " GB"
  if (abs >= 1048576) return (value / 1048576).toFixed(1) + " MB"
  return (value / 1024).toFixed(1) + " KB"
}

function fmtCount(value) {
  return Math.round(value).toLocaleString()
}

function fmtPercent(value) {
  return value.toFixed(1) + " %"
}

const FORMATTERS = { bytes: fmtBytes, count: fmtCount, percent: fmtPercent }

export const TimeseriesChart = {
  mounted() {
    this.colorSlots = {} // series name -> palette slot, stable per page
    this.data = null
    this.chart = null
    this.lines = [] // [{name, line, lastValue}]

    this.chartEl = document.createElement("div")
    this.chartEl.style.width = "100%"
    this.chartEl.style.height = this.el.dataset.height || "320px"
    this.emptyEl = document.createElement("div")
    this.emptyEl.className =
      "hidden items-center justify-center text-sm text-base-content/50"
    this.emptyEl.style.height = this.el.dataset.height || "320px"
    this.emptyEl.textContent =
      "No data points for this metric in the selected window — try another metric."
    this.legendEl = document.createElement("div")
    this.legendEl.className = "flex flex-wrap gap-x-4 gap-y-1 pt-2 text-sm"
    this.el.appendChild(this.chartEl)
    this.el.appendChild(this.emptyEl)
    this.el.appendChild(this.legendEl)

    this.handleEvent(`chart-data-${this.el.id}`, (payload) => {
      this.data = payload
      this.render()
    })

    // Handshake: data pushed during the LiveView's mount/handle_params can be
    // dispatched before this hook registers its handler and silently dropped.
    // Announce readiness so the server (re)pushes the data afterwards.
    this.pushEvent("chart-ready", { id: this.el.id })

    // re-color when the admin theme toggle stamps <html data-theme>
    this.themeObserver = new MutationObserver(() => this.render())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })

    this.resizeObserver = new ResizeObserver(() => {
      if (this.chart) this.chart.applyOptions({ width: this.chartEl.clientWidth })
    })
    this.resizeObserver.observe(this.chartEl)
  },

  destroyed() {
    if (this.themeObserver) this.themeObserver.disconnect()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.chart) this.chart.remove()
  },

  slotFor(name) {
    if (!(name in this.colorSlots)) {
      const used = new Set(Object.values(this.colorSlots))
      let slot = 0
      while (used.has(slot)) slot++
      this.colorSlots[name] = slot
    }
    return this.colorSlots[name]
  },

  formatter() {
    const kind = this.data && this.data.value_kind
    return FORMATTERS[kind] || fmtCount
  },

  render() {
    if (!this.data) return
    const mode = themeMode()
    const palette = PALETTE[mode]
    const chrome = CHROME[mode]
    const fmt = this.formatter()

    if (this.chart) {
      this.chart.remove()
      this.chart = null
    }

    const totalPoints = this.data.series.reduce((n, s) => n + s.points.length, 0)
    if (totalPoints === 0) {
      this.chartEl.style.display = "none"
      this.emptyEl.classList.remove("hidden")
      this.emptyEl.classList.add("flex")
      this.legendEl.innerHTML = ""
      this.lines = []
      return
    }
    this.chartEl.style.display = ""
    this.emptyEl.classList.add("hidden")
    this.emptyEl.classList.remove("flex")

    this.chart = createChart(this.chartEl, {
      width: this.chartEl.clientWidth,
      height: this.chartEl.clientHeight,
      layout: {
        background: { type: ColorType.Solid, color: "transparent" },
        textColor: chrome.text,
        fontFamily: "system-ui, -apple-system, sans-serif",
        fontSize: 12,
        attributionLogo: false,
      },
      grid: {
        vertLines: { color: chrome.grid },
        horzLines: { color: chrome.grid },
      },
      crosshair: { mode: CrosshairMode.Normal },
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: chrome.grid,
      },
      rightPriceScale: { borderColor: chrome.grid },
      localization: { priceFormatter: fmt },
      handleScroll: { mouseWheel: false },
      handleScale: { mouseWheel: false },
    })

    const shown = this.data.series.slice(0, MAX_SERIES)
    this.lines = shown.map((s) => {
      const color = palette[this.slotFor(s.name) % palette.length]
      const line = this.chart.addSeries(LineSeries, {
        color: color,
        lineWidth: 2,
        priceLineVisible: false,
        lastValueVisible: false,
        crosshairMarkerRadius: 4,
      })
      line.setData(s.points.map(([t, v]) => ({ time: t, value: v })))
      const last = s.points.length > 0 ? s.points[s.points.length - 1][1] : null
      return { name: s.name, color: color, line: line, lastValue: last }
    })

    this.chart.timeScale().fitContent()
    this.renderLegend(this.lines.map((l) => l.lastValue))

    // crosshair tooltip: the legend doubles as the value readout
    this.chart.subscribeCrosshairMove((param) => {
      if (param && param.time && param.seriesData) {
        this.renderLegend(
          this.lines.map((l) => {
            const point = param.seriesData.get(l.line)
            return point ? point.value : null
          })
        )
      } else {
        this.renderLegend(this.lines.map((l) => l.lastValue))
      }
    })
  },

  renderLegend(values) {
    const fmt = this.formatter()
    const hidden = this.data.series.length - this.lines.length

    this.legendEl.innerHTML = ""
    this.lines.forEach((l, i) => {
      const item = document.createElement("span")
      item.className = "inline-flex items-center gap-1.5"

      const swatch = document.createElement("span")
      swatch.style.cssText = `display:inline-block;width:14px;height:3px;border-radius:2px;background:${l.color}`

      const label = document.createElement("span")
      label.textContent = l.name
      label.className = "text-base-content/70"

      item.appendChild(swatch)
      item.appendChild(label)

      if (values[i] !== null && values[i] !== undefined) {
        const value = document.createElement("span")
        value.textContent = fmt(values[i])
        value.className = "tabular-nums font-medium"
        item.appendChild(value)
      }

      this.legendEl.appendChild(item)
    })

    if (hidden > 0) {
      const note = document.createElement("span")
      note.textContent = `+${hidden} more not shown`
      note.className = "text-base-content/50"
      this.legendEl.appendChild(note)
    }
  },
}
