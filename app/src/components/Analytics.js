import React from 'react'
import moment from 'moment'
import { Line } from 'react-chartjs-2'
import './Analytics.css'

const COLOR = '#009663'

const getChartDataFromHistory = (history = []) => {
  return {
    labels: history ? history.map(data => moment(data.datetime).utc()) : [],
    datasets: [{
      fill: true,
      borderColor: COLOR,
      borderWidth: 1,
      backgroundColor: 'rgba(239, 242, 236, 0.5)',
      pointBorderWidth: 2,
      pointRadius: 1,
      strokeColor: COLOR,
      data: history ? history.map(data => data.followersCount) : []
    }]
  }
}

const chartOptions = {
  responsive: true,
  showTooltips: false,
  pointDot: false,
  scaleShowLabels: false,
  datasetFill: false,
  scaleFontSize: 0,
  animation: false,
  legend: {
    display: false
  },
  scales: {
    yAxes: [{
      ticks: {
        display: false,
        beginAtZero: false
      },
      gridLines: {
        drawBorder: false,
        display: false
      }
    }],
    xAxes: [{
      gridLines: {
        drawBorder: false,
        display: false
      },
      ticks: {
        display: false
      }
    }]
  }
}

const Analytics = ({
  twitter = {
    history: {
      loading: true,
      items: []
    },
    data: {
      loading: true,
      followersCount: undefined
    }
  }
}) => {
  const chartData = getChartDataFromHistory(twitter.history.items)
  return (
    <div className='analytics'>
      <h2>Analytics</h2>
      <hr />
      <div className='analytics-trend-row'>
        <div className='analytics-trend-info'>
          <div className='analytics-trend-title'>
            Twitter followers
          </div>
          <div className='analytics-trend-details'>
            {twitter.data.loading ? '---' : twitter.data.followersCount}
          </div>
        </div>
        <div className='analytics-trend-chart'>
          <Line
            height={80}
            data={chartData}
            options={chartOptions}
            style={{ transition: 'opacity 0.25s ease' }}
            redraw
          />
        </div>
      </div>
    </div>
  )
}

export default Analytics
