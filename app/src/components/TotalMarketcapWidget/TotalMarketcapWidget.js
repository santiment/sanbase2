import React from 'react'
import moment from 'moment'
import { graphql } from 'react-apollo'
import { ResponsiveContainer, AreaChart, Area, XAxis, Legend } from 'recharts'
import Widget from '../Widget/Widget'
import { totalMarketcapGQL } from './TotalMarketcapGQL'
import { formatNumber } from '../../utils/formatting'
import './TotalMarketcapWidget.scss'

const currencyFormatOptions = {
  currency: 'USD',
  minimumFractionDigits: 0,
  maximumFractionDigits: 0
}

const combineHistoryPrices = historyPrices => {
  if (!historyPrices) return undefined

  const prices = Object.keys(historyPrices)

  if (prices.length > 10) return undefined // OTHERWISE: It's computing hell. Almost 1000 of arrays with 100+ elements.

  return prices.reduce((acc, slug) => {
    if (historyPrices[slug] === undefined) return []
    return historyPrices[slug].map((pricePoint, index) => {
      let doesAccumulatorExist = acc[index] !== undefined
      let accVolume = doesAccumulatorExist ? acc[index].volume : 0
      let accMarketcap = doesAccumulatorExist ? acc[index].marketcap : 0

      return {
        volume: pricePoint.volume + accVolume,
        marketcap: pricePoint.marketcap + accMarketcap
      }
    })
  }, [])
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

const mergeProjectWithTotal = (total, lastIndex, project, projectName) => {
  const project_LAST_INDEX = project.length - 1
  for (let i = project_LAST_INDEX; i > -1; i--) {
    total[lastIndex][constructProjectMarketcapKey(projectName)] =
      project[i].marketcap
    lastIndex--
  }
}

const combineDataset = (totalMarketHistory, restProjects) => {
  const LAST_INDEX = totalMarketHistory.length - 1
  if (LAST_INDEX < 0) {
    return
  }

  for (const key of Object.keys(restProjects)) {
    mergeProjectWithTotal(
      totalMarketHistory,
      LAST_INDEX,
      restProjects[key],
      key
    )
  }
  console.log(totalMarketHistory)
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
  const {
    totalmarketCapPrice = '.',
    volumeAmplitudePrice = '.',
    marketcapDataset = []
  } = generateWidgetData(TOTAL_MARKET)

  let restAreas = null

  if (!loading && Object.keys(restProjects).length > 0) {
    combineDataset(marketcapDataset, restProjects)
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
