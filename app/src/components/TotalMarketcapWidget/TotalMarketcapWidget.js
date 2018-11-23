import React from 'react'
import { ResponsiveContainer, AreaChart, Area, XAxis } from 'recharts'
import Widget from '../Widget/Widget'
import { formatNumber } from '../../utils/formatting'
import { mergeTimeseriesByKey } from '../../utils/utils'
import './TotalMarketcapWidget.scss'

const currencyFormatOptions = {
  currency: 'USD',
  minimumFractionDigits: 0,
  maximumFractionDigits: 0
}

const generateWidgetData = historyPrice => {
  if (!historyPrice || historyPrice.length === 0) return {}

  const historyPriceLastIndex = historyPrice.length - 1

  const marketcapDataset = historyPrice.map(data => ({
    datetime: data.datetime,
    marketcap: data.marketcap
  }))

  const volumeAmplitude =
    historyPrice[historyPriceLastIndex].volume -
    historyPrice[historyPriceLastIndex - 1].volume

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
    marketcapDataset
  }
}

const constructProjectMarketcapKey = projectName => `${projectName}-marketcap`

const combineDataset = (totalMarketHistory, restProjects) => {
  const LAST_INDEX = totalMarketHistory.length - 1
  if (LAST_INDEX < 0) {
    return
  }
  
  const restProjectTimeseries = Object.keys(restProjects).map(key =>
    restProjects[key].map(({ marketcap, datetime }) => ({
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

const COLORS = ['#ffa000', '#1111bb', '#ab47bc']

const getTop3Area = restProjects => {
  return Object.keys(restProjects).map((key, i) => (
    <Area
      key={key}
      dataKey={constructProjectMarketcapKey(key)}
      type='monotone'
      strokeWidth={1}
      stroke={COLORS[i]}
      fill={COLORS[i] + '44'}
      isAnimationActive={false}
    />
  ))
}

const TotalMarketcapWidget = ({
  historyPrices: { TOTAL_MARKET, ...restProjects },
  loading
}) => {
  let {
    totalmarketCapPrice = '.',
    volumeAmplitudePrice = '.',
    marketcapDataset = []
  } = generateWidgetData(TOTAL_MARKET)

  let restAreas = null

  if (!loading && Object.keys(restProjects).length > 0) {
    marketcapDataset = combineDataset(marketcapDataset, restProjects)
    restAreas = getTop3Area(restProjects)
  }

  const valueClassNames = `TotalMarketcapWidget__value ${
    totalmarketCapPrice === '.' ? 'TotalMarketcapWidget__value_loading' : ''
  }`

  return (
    <Widget className='TotalMarketcapWidget'>
      <div className='TotalMarketcapWidget__info'>
        <div className='TotalMarketcapWidget__left'>
          <h3 className='TotalMarketcapWidget__label'>Total marketcap</h3>
          <h4 className={valueClassNames}>{totalmarketCapPrice}</h4>
        </div>
        <div className='TotalMarketcapWidget__right'>
          <h3 className='TotalMarketcapWidget__label'>Vol 24 hr</h3>
          <h4 className={valueClassNames}>{volumeAmplitudePrice}</h4>
        </div>
      </div>
      <ResponsiveContainer width='100%' className='TotalMarketcapWidget__chart'>
        <AreaChart
          data={marketcapDataset}
          margin={{ top: 0, right: 0, left: 0, bottom: 0 }}
        >
          <XAxis dataKey='datetime' hide />
          <Area
            dataKey='marketcap'
            type='monotone'
            strokeWidth={1}
            stroke='#2d5e39'
            fill='rgba(214, 235, 219, .8)'
            isAnimationActive={false}
          />
          {restAreas}
        </AreaChart>
      </ResponsiveContainer>
    </Widget>
  )
}

export default TotalMarketcapWidget
