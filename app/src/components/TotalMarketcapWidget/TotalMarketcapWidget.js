import React from 'react'
import moment from 'moment'
import { graphql } from 'react-apollo'
import { Line } from 'react-chartjs-2'
import { totalMarketcapGQL } from './TotalMarketcapGQL'
import { formatNumber } from '../../utils/formatting'
import './TotalMarketcapWidget.css'

const chartOptions = {
  pointRadius: 0,
  legend: {
    display: false
  },
  elements: {
    point: {
      hitRadius: 1,
      hoverRadius: 1,
      radius: 0
    }
  },
  tooltips: {
    mode: 'x',
    intersect: false,
    titleMarginBottom: 10,
    titleFontSize: 13,
    titleFontColor: '#3d4450',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    cornerRadius: 3,
    borderColor: 'rgba(38, 43, 51, 0.7)',
    borderWidth: 1,
    bodyFontSize: 12,
    bodySpacing: 8,
    bodyFontColor: '#3d4450',
    displayColors: true,
    callbacks: {
      title: item => {
        return moment(item[0].xLabel).format('MMM DD YYYY')
      },
      label: tooltipItem =>
        formatNumber(tooltipItem.yLabel, {
          currency: 'USD'
        })
    }
  },
  scales: {
    yAxes: [
      {
        display: false
      }
    ],
    xAxes: [
      {
        display: false
      }
    ]
  }
}

const options = {
  borderColor: 'rgba(45, 94, 57, 1)',
  borderWidth: 1,
  lineTension: 0.1,
  pointBorderWidth: 1,
  backgroundColor: 'rgba(214, 235, 219, .8)'
}

const currencyFormatOptions = {
  currency: 'USD',
  minimumFractionDigits: 0,
  maximumFractionDigits: 0
}

const generateWidgetData = historyPrice => {
  if (!historyPrice) return {}

  const historyPriceLastIndex = historyPrice.length - 1

  const marketcapDataset = {
    labels: historyPrice.map(data => data.datetime),
    datasets: [
      {
        data: historyPrice.map(data => data.marketcap),
        label: 'Marketcap',
        ...options
      }
    ]
  }

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

const TotalMarketcapWidget = ({ data: { historyPrice } }) => {
  const {
    totalmarketCapPrice = '.',
    volumeAmplitudePrice = '.',
    marketcapDataset = {}
  } = generateWidgetData(historyPrice)

  const valueClassNames = `TotalMarketcapWidget__value ${
    totalmarketCapPrice === '.' ? 'TotalMarketcapWidget__value_loading' : ''
  }`

  return (
    <div className='TotalMarketcapWidget'>
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
      <Line
        data={marketcapDataset}
        options={chartOptions}
        className='TotalMarketcapWidget__chart'
      />
    </div>
  )
}

const ApolloTotalMarketcapWidget = graphql(totalMarketcapGQL)(
  TotalMarketcapWidget
)

ApolloTotalMarketcapWidget.defaultProps = {
  from: moment()
    .subtract(3, 'months')
    .utc()
    .format(),
  slug: 'TOTAL_MARKET'
}

export default ApolloTotalMarketcapWidget
