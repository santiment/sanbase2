import React from 'react'
import moment from 'moment'
import { graphql } from 'react-apollo'
import { ResponsiveContainer, AreaChart, Area, XAxis } from 'recharts'
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

  if (prices.length > 10) return undefined // OTHERWISE: It's computing hell. Almost 1000 of arrays with 500+ elements.

  return prices.reduce((acc, slug) => {
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

const TotalMarketcapWidget = ({ historyPrices }) => {
  const {
    totalmarketCapPrice = '.',
    volumeAmplitudePrice = '.',
    marketcapDataset = []
  } = generateWidgetData(combineHistoryPrices(historyPrices))

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
        </AreaChart>
      </ResponsiveContainer>
    </Widget>
  )
}

export default TotalMarketcapWidget
