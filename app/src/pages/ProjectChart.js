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
          const price = data.priceBtc
          return price > 1 ? price.toFixed(2) : price.toFixed(8)
        }
        return data.priceUsd
      }) : []
    }]
  }
}

const ProjectChart = ({
  showBTC,
  showUSD,
  show1d,
  show1w,
  show2w,
  show1m,
  isToggledBTC,
  filter,
  historyPrice
}) => {
  if (historyPrice.loading) {
    return (
      <h2>Loading...</h2>
    )
  }
  console.log(historyPrice.historyPrice)
  const chartData = getChartDataFromHistory(historyPrice.historyPrice, isToggledBTC)
  const chartOptions = {
    responsive: true,
    showTooltips: false,
    pointDot: false,
    scaleShowLabels: false,
    datasetFill: false,
    scaleFontSize: 0,
    animation: false,
    pointRadius: 0,
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
          display: true,
          beginAtZero: true
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
    <div>
      {isToggledBTC ? 'show BTC' : 'show USD'}
      <button onClick={showBTC}>BTC</button>
      <button onClick={showUSD}>USD</button>
      <button onClick={show1d}>1d</button>
      <button onClick={show1w}>1w</button>
      <button onClick={show2w}>2w</button>
      <button onClick={show1m}>2m</button>
      {filter}
      <Line
        data={chartData}
        options={chartOptions}
        onElementsClick={elems => {
          console.log(elems[0]._index)
        }}
        style={{ transition: 'opacity 0.25s ease' }}
        redraw
      />
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

const enhance = compose(
  withState('isToggledBTC', 'currencyToggle', false),
  withHandlers({
    showBTC: ({ currencyToggle }) => e => currencyToggle(true),
    showUSD: ({ currencyToggle }) => e => currencyToggle(false)
  }),
  withState('filter', 'setFilter', '1d'),
  withHandlers({
    show1d: ({ setFilter }) => e => setFilter('1d'),
    show1w: ({ setFilter }) => e => setFilter('1w'),
    show2w: ({ setFilter }) => e => setFilter('2w'),
    show1m: ({ setFilter }) => e => setFilter('1m')
  }),
  graphql(getHistoryGQL, {
    name: 'historyPrice',
    options: ({ticker}) => ({
      variables: {
        'ticker': ticker,
        'from': '2017-11-14 09:14:31Z',
        'to': '2017-12-14 09:14:31Z',
        'interval': '1h'
      }
    })
  }),
  pure
)

export default enhance(ProjectChart)
