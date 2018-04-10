import React from 'react'
import moment from 'moment'
import { Line } from 'react-chartjs-2'
import { Icon } from 'semantic-ui-react'
import { formatNumber } from './../utils/formatting'
import './Analytics.css'

const COLOR = '#009663'

const makeAxisName = label => 'y-axis-' + label

const getChartDataFromHistory = (data, label) => {
  const items = data.items || []
  const borderColor = (data.dataset || {}).borderColor || COLOR
  return {
    labels: items ? items.map(data => moment(data.datetime).utc()) : [],
    datasets: [{
      label,
      type: 'LineWithLine',
      fill: true,
      borderColor: borderColor,
      borderWidth: 0.5,
      yAxisID: makeAxisName(label),
      backgroundColor: borderColor,
      pointBorderWidth: 0.2,
      pointRadius: 0.1,
      data: items ? items.map(data => data[`${label}`]) : [],
      datalabels: {
        display: false
      }
    }]
  }
}

const getChartOptions = (label) => ({
  responsive: true,
  showTooltips: false,
  pointDot: false,
  scaleShowLabels: false,
  datasetFill: false,
  scaleFontSize: 0,
  animation: false,
  maintainAspectRatio: false,
  hover: {
    mode: 'x',
    intersect: false
  },
  tooltips: {
    mode: 'x',
    intersect: false
  },
  legend: {
    display: false
  },
  scales: {
    yAxes: [{
      id: makeAxisName(label),
      ticks: {
        display: false,
        beginAtZero: true
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
})

const renderData = (data, label) => {
  if (data.loading) {
    return ('Loading ...')
  }
  if (data.error) {
    return ('Server error. Try later...')
  }
  if (!data.loading && data.items.length === 0) {
    return ('No data')
  }
  const value = data.items[data.items.length - 1][`${label}`]
  //return formatNumber(value, { currency: 'USD' })
  return formatNumber(value)
}

const Analytics = ({
  data = {
    dataset: {
      borderColor: COLOR
    },
    error: false,
    loading: true,
    items: []
  },
  label,
  show = 'last 7 days'
}) => {
  const chartData = getChartDataFromHistory(data, label)
  const chartOptions = getChartOptions(label)
  const borderColor = (data.dataset || {}).borderColor || COLOR
  return (
    <div className='analytics'>
      <div className='analytics-trend-row'>
        <div className='analytics-trend-info-label'>
          <Icon name='arrow down' /> {show}
        </div>
      </div>
      <div className='analytics-trend-row'>
        <div className='analytics-trend-info'>
          <div
            className='analytics-trend-details'
            style={{color: borderColor}}
          >
            {renderData(data, label)}
          </div>
        </div>
        <div className='analytics-trend-chart'>
          <Line
            data={chartData}
            options={chartOptions}
          />
        </div>
      </div>
    </div>
  )
}

export default Analytics
