import React from 'react'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import {
  compose,
  pure,
  withState,
  withHandlers
} from 'recompose'
import { Line } from 'react-chartjs-2'
import moment from 'moment'
import { formatNumber } from '../utils/formatting'
import './ProjectChart.css'

const normalizeBTC = price => price > 1 ? price.toFixed(2) : price.toFixed(8)

const TimeFilter = ({filter, setFilter, disabled}) => (
  <div className='time-filter'>
    <button
      className={filter === '1d' ? 'activated' : ''}
      disabled={disabled}
      onClick={() => setFilter('1d')}>1d</button>
    <button
      className={filter === '1w' ? 'activated' : ''}
      disabled={disabled}
      onClick={() => setFilter('1w')}>1w</button>
    <button
      className={filter === '2w' ? 'activated' : ''}
      disabled={disabled}
      onClick={() => setFilter('2w')}>2w</button>
    <button
      className={filter === '1m' ? 'activated' : ''}
      disabled={disabled}
      onClick={() => setFilter('1m')}>1m</button>
  </div>
)

const CurrencyFilter = ({isToggledBTC, showBTC, showUSD}) => (
  <div className='currency-filter'>
    <button
      className={isToggledBTC ? 'activated' : ''}
      onClick={showBTC}>BTC</button>
    <button
      className={!isToggledBTC ? 'activated' : ''}
      onClick={showUSD}>USD</button>
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
          return normalizeBTC(price)
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
  if (historyPrice.loading) {
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
            ? normalizeBTC(tooltipItem.yLabel)
            : formatNumber(tooltipItem.yLabel, 'USD')
        }
      }
    },
    legend: {
      display: false
    },
    elements: {
      point: {
        hitRadius: 10,
        hoverRadius: 10,
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
        <div>{selected
          ? <div>
            {props.isToggledBTC
              ? normalizeBTC(parseFloat(chartData.datasets[0].data[selected]))
              : formatNumber(chartData.datasets[0].data[selected], 'USD')}
            &nbsp;|&nbsp;
            {moment(chartData.labels[selected]).format('YYYY-MM-DD')}
          </div>
        : ''}</div>
      </div>
      <Line
        className='graph'
        data={chartData}
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
  query history($ticker: String!, $from: DateTime!, $to:DateTime!, $interval: String) {
    historyPrice (
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime
    }
}`

const defaultFrom = moment().subtract(1, 'month').utc().format()
const defaultTo = moment().utc().format()

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
    options: ({ticker}) => ({
      variables: {
        'ticker': ticker,
        'from': defaultFrom,
        'to': defaultTo,
        'interval': '1h'
      }
    })
  }),
  pure
)

export default enhance(ProjectChart)
