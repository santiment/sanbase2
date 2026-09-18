import type { CandlePoint, ChartData, ChartSeries, SeriesSummary } from './contract'

const HOUR = 3600
const POINTS = 168
const NOW = Math.floor(Date.now() / 1000)

const at = (i: number) => NOW - (POINTS - i) * HOUR

function generateCandles(): CandlePoint[] {
  let price = 64_000
  return Array.from({ length: POINTS + 1 }, (_, i) => {
    const open = price
    const close = Math.max(45_000, open + (Math.random() - 0.45) * 400)
    const high = Math.max(open, close) + Math.random() * 250
    const low = Math.min(open, close) - Math.random() * 250
    price = close
    return { time: at(i), open, high, low, close }
  })
}

function generateValues(): { time: number; value: number }[] {
  let v = 5_000
  return Array.from({ length: POINTS + 1 }, (_, i) => {
    v = Math.max(500, v + (Math.random() - 0.5) * 1500)
    return { time: at(i), value: Math.round(v) }
  })
}

const pct = (from: number, to: number) =>
  from === 0 ? 0 : ((to - from) / from) * 100

function summarize(
  label: string,
  unit: SeriesSummary['unit'],
  first: number,
  last: number,
): SeriesSummary {
  return { label, unit, current: last, change_pct: pct(first, last) }
}

const candles = generateCandles()
const overlay = generateValues()

const primary: ChartSeries = {
  id: 'primary',
  name: 'price_usd',
  label: 'Price USD',
  style: 'candles',
  color: '#26a69a',
  pane: 0,
  unit: 'usd',
  data: candles,
}

const overlaySeries: ChartSeries = {
  id: 'overlay',
  name: 'social_volume_total',
  label: 'Social volume',
  style: 'histogram',
  color: '#4a90e2',
  pane: 1,
  unit: '',
  data: overlay,
}

export const CHART_MOCK: ChartData = {
  slug: 'bitcoin',
  range: '7d',
  interval: '1h',
  period_start: new Date(candles[0].time * 1000).toISOString(),
  period_end: new Date(candles.at(-1)!.time * 1000).toISOString(),
  summary: {
    primary: summarize('Price USD', 'usd', candles[0].close, candles.at(-1)!.close),
    overlay: summarize('Social volume', '', overlay[0].value, overlay.at(-1)!.value),
  },
  series: [primary, overlaySeries],
}
