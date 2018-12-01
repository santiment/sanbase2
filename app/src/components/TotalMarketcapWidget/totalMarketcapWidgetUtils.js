import React from 'react'
import { Area } from 'recharts'

import { formatNumber } from '../../utils/formatting'
import { mergeTimeseriesByKey } from '../../utils/utils'

const COLORS = ['#dda000', '#1111bb', '#ab47bc']
const COLORS_TEXT = ['#aa7000', '#111199', '#8a43ac']

const currencyFormatOptions = {
  currency: 'USD',
  minimumFractionDigits: 0,
  maximumFractionDigits: 0
}

export const generateWidgetData = historyPrice => {
  if (!historyPrice || historyPrice.length === 0) return {}

  const historyPriceLastIndex = historyPrice.length - 1

  const marketcapDataset = historyPrice.map(data => ({
    datetime: data.datetime,
    marketcap: data.marketcap
  }))

  const volumeAmplitude =
    historyPrice[historyPriceLastIndex].volume -
    historyPrice[historyPriceLastIndex - 1].volume

  const volume24PercentChange =
    (1 -
      historyPrice[historyPriceLastIndex].volume /
        historyPrice[historyPriceLastIndex - 1].volume) *
    -100

  const volumeAmplitudePrice = formatNumber(
    volumeAmplitude,
    currencyFormatOptions
  )

  const totalmarketCapPrice = formatNumber(
    historyPrice[historyPriceLastIndex].marketcap,
    currencyFormatOptions
  )

  return {
    totalmarketCapPrice,
    volumeAmplitudePrice,
    volume24PercentChange,
    marketcapDataset
  }
}

const constructProjectMarketcapKey = projectName => `${projectName}-marketcap`

export const combineDataset = (totalMarketHistory, restProjects) => {
  const LAST_INDEX = totalMarketHistory.length - 1
  if (LAST_INDEX < 0) {
    return
  }

  const restProjectTimeseries = Object.keys(restProjects).map(key =>
    (restProjects[key] || []).map(({ marketcap, datetime }) => ({
      datetime,
      [constructProjectMarketcapKey(key)]: marketcap
    }))
  )

  const result = mergeTimeseriesByKey({
    timeseries: [totalMarketHistory, ...restProjectTimeseries],
    key: 'datetime'
  })

  return result
}

export const getTop3Area = restProjects => {
  return Object.keys(restProjects).map((key, i) => {
    const rightMarginByIndex = (i + 1) * 16
    return (
      <Area
        key={key}
        dataKey={constructProjectMarketcapKey(key)}
        type='monotone'
        strokeWidth={1}
        stroke={COLORS[i]}
        label={({ x, y, index }) => {
          if (index === rightMarginByIndex) {
            return (
              <text
                x={x}
                y={y}
                dy={-8}
                fill={COLORS_TEXT[i]}
                fontSize={12}
                textAnchor='middle'
              >
                {key}
              </text>
            )
          }
          return ''
        }}
        fill={COLORS[i] + '2c'}
        isAnimationActive={false}
      />
    )
  })
}
