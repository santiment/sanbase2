import React from 'react'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import {
  compose,
  pure,
  withState,
  withHandlers
} from 'recompose'
import { Merge } from 'animate-components'
import { fadeIn, slideUp } from 'animate-keyframes'
import { Line } from 'react-chartjs-2'
import moment from 'moment'
import { formatNumber, formatBTC } from '../utils/formatting'
import './ProjectChart.css'

const TimeFilterItem = ({disabled, filter, setFilter, value = '1d'}) => {
  let cls = filter === value ? 'activated' : ''
  if (disabled) {
    cls += ' disabled'
  }
  return (
    <div
      className={cls}
      onClick={() => !disabled && setFilter(value)}>{value}</div>
  )
}

const TimeFilter = props => (
  <div className='time-filter'>
    <TimeFilterItem value={'1d'} {...props} />
    <TimeFilterItem value={'1w'} {...props} />
    <TimeFilterItem value={'2w'} {...props} />
    <TimeFilterItem value={'1m'} {...props} />
  </div>
)

const CurrencyFilter = ({isToggledBTC, showBTC, showUSD}) => (
  <div className='currency-filter'>
    <div
      className={isToggledBTC ? 'activated' : ''}
      onClick={showBTC}>BTC</div>
    <div
      className={!isToggledBTC ? 'activated' : ''}
      onClick={showUSD}>USD</div>
  </div>
)

const getChartDataFromHistory = (history = [], isToggledBTC) => {
  return {
    labels: history ? history.map(data => new Date(data.datetime)) : [],
    datasets: [{
      strokeColor: '#7a9d83eb',
      borderColor: '#7a9d83eb',
      borderWidth: 1,
      backgroundColor: 'rgba(239, 242, 236, 0.5)',
      pointBorderWidth: 0,
      data: history ? history.map(data => {
        if (isToggledBTC) {
          const price = parseFloat(data.priceBtc)
          return formatBTC(price)
        }
        return data.priceUsd
      }) : []
    }]
  }
}

const ProjectChart = ({
  historyPrice,
  setSelected,
  selected,
  ...props
}) => {
  if (!historyPrice || historyPrice.loading) {
    return (
      <h2>Loading...</h2>
    )
  }
  const chartData = getChartDataFromHistory(historyPrice.historyPrice, props.isToggledBTC)
  const chartOptions = {
    responsive: true,
    showTooltips: false,
    pointDot: false,
    scaleShowLabels: false,
    datasetFill: false,
    scaleFontSize: 0,
    animation: false,
    pointRadius: 0,
    tooltips: {
      callbacks: {
        title: item => '',
        label: (tooltipItem, data) => {
          return props.isToggledBTC
            ? formatBTC(tooltipItem.yLabel)
            : formatNumber(tooltipItem.yLabel, 'USD')
        }
      }
    },
    legend: {
      display: false
    },
    elements: {
      point: {
        hitRadius: 2,
        hoverRadius: 2,
        radius: 0
      }
    },
    scales: {
      yAxes: [{
        ticks: {
          display: true
        },
        gridLines: {
          drawBorder: true,
          display: true
        }
      }],
      xAxes: [{
        type: 'time',
        time: {
          displayFormats: {
            quarter: 'MMM YYYY'
          }
        },
        ticks: {
          autoSkipPadding: 1
        },
        gridLines: {
          drawBorder: true,
          display: true
        }
      }]
    }
  }

  return (
    <div className='project-dp-chart'>
      <div className='chart-header'>
        <TimeFilter disabled {...props} />
        <div className='selected-value'>{selected &&
          <Merge
            one={{ name: fadeIn, duration: '0.3s', timingFunction: 'ease-in' }}
            two={{ name: slideUp, duration: '0.5s', timingFunction: 'ease-out' }}
            as='div'
          >
            <span className='selected-value-datetime'>{moment(chartData.labels[selected]).format('MMMM DD, YYYY')}</span>
            <span className='selected-value-data'>{props.isToggledBTC
              ? formatBTC(parseFloat(chartData.datasets[0].data[selected]))
              : formatNumber(chartData.datasets[0].data[selected], 'USD')}</span>
          </Merge>}</div>
      </div>
      <Line
        className='graph'
        data={chartData}
        redraw
        options={chartOptions}
        onElementsClick={elems => {
          elems[0] && setSelected(elems[0]._index)
        }}
        style={{ transition: 'opacity 0.25s ease' }}
      />
      <CurrencyFilter {...props} />
    </div>
  )
}

const getHistoryGQL = gql`
  query history($ticker: String, $from: DateTime, $to: DateTime, $interval: String) {
    historyPrice(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime,
      marketcap
    }
}`

const defaultFrom = moment().subtract(1, 'M').utc().format()
const defaultTo = moment().subtract(1, 'd').utc().format()

const enhance = compose(
  withState('isToggledBTC', 'currencyToggle', false),
  withHandlers({
    showBTC: ({ currencyToggle }) => e => currencyToggle(true),
    showUSD: ({ currencyToggle }) => e => currencyToggle(false)
  }),
  withState('filter', 'setFilter', '1m'),
  withState('selected', 'setSelected', null),
  graphql(getHistoryGQL, {
    name: 'historyPrice',
    options: ({ticker}) => {
      return {
        variables: {
          'ticker': ticker,
          'from': defaultFrom,
          'to': defaultTo,
          'interval': '10h'
        }
      }
    }
  }),
  pure
)

export default enhance(ProjectChart)
