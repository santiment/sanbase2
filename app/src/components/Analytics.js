import React from 'react'
import moment from 'moment'
import { compose, withState } from 'recompose'
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  LineChart,
  Line,
  Tooltip,
  ReferenceLine,
  Brush
} from 'recharts'
import { formatNumber } from './../utils/formatting'
import './Analytics.css'

const COLOR = '#009663'

const makeAxisName = label => 'y-axis-' + label

const getChartDataFromHistory = (data, label, chart = {}) => {
  const items = data.items || []
  const borderColor = (data.dataset || {}).borderColor || COLOR
  return {
    labels: items ? items.map(data => moment(data.datetime).utc()) : [],
    datasets: [{
      label,
      type: chart.type || 'LineWithLine',
      fill: chart.fill || true,
      borderColor: borderColor,
      borderWidth: chart.borderWidth || 0.5,
      yAxisID: makeAxisName(label),
      backgroundColor: borderColor,
      pointBorderWidth: chart.pointBorderWidth || 0.2,
      pointRadius: 0.1,
      data: items ? items.map(data => ({
        x: data.datetime,
        y: +data[`${label}`]
      })) : [],
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
  scaleShowLabels: true,
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
    intersect: false,
    titleMarginBottom: 16,
    titleFontSize: 14,
    titleFontColor: '#3d4450',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    cornerRadius: 3,
    borderColor: 'rgba(38, 43, 51, 0.7)',
    borderWidth: 1,
    bodyFontSize: 14,
    bodySpacing: 8,
    bodyFontColor: '#3d4450',
    displayColors: true,
    callbacks: {
      title: (item, data) => {
        return moment(data.datasets[0].data[item[0].index].x).format('MMM DD YYYY')
      },
      label: (tooltipItem, data) => {
        const label = data.datasets[tooltipItem.datasetIndex].label.toString()
        return `${label}: ${formatNumber(tooltipItem.yLabel, { currency: 'USD' })}`
      }
    }
  },
  legend: {
    display: false
  },
  scales: {
    yAxes: [{
      id: makeAxisName(label),
      ticks: {
        display: false,
        beginAtZero: false
      },
      gridLines: {
        drawBorder: false,
        display: true
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

const renderData = (data, label, formatData = null) => {
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
  if (formatData) {
    return formatData(value)
  }
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
  chart = {
    type: 'line',
    referenceLine: {
      color: 'red',
      y: null,
      label: ''
    },
    withMiniMap: false
  },
  show = 'last 7 days',
  setIndex,
  index = null,
  formatData = null,
  showInfo = true
}) => {
  const chartData = getChartDataFromHistory(data, label, chart)
  const borderColor = (data.dataset || {}).borderColor || chart.color || COLOR
  const {referenceLine, withMiniMap, syncId = undefined} = chart
  return (
    <div className='analytics'>
      <div className='analytics-trend-row'>
        <div className='analytics-trend-info-label'>
          {show}
          {showInfo &&
          <div className='analytics-trend-info'>
            <div
              className='analytics-trend-details'
              style={{color: borderColor}}
            >
              {index
              ? (data.items[index] || {})[`${label}`]
              : renderData(data, label, formatData)}
            </div>
          </div>}
        </div>
      </div>
      <div className='analytics-trend-row'>
        <div className='analytics-trend-chart'>
          {chart.type === 'bar' &&
            <ResponsiveContainer>
              <BarChart
                syncId={syncId}
                data={chartData.datasets[0].data} >
                <Tooltip />
                <Bar dataKey='y' stroke={borderColor} fill={borderColor} />
                {withMiniMap &&
                <Brush
                  travellerWidth={20}
                  data={chartData.datasets[0].data}
                  tickFormatter={tick => moment(tick).format('MM.DD.YYYY')}
                  dataKey='x' height={50} />}
              </BarChart>
            </ResponsiveContainer>}
          {chart.type === 'line' &&
            <ResponsiveContainer>
              <LineChart
                syncId='anyId'
                dot={false}
                data={chartData.datasets[0].data} >
                <Line
                  type='monotone'
                  dot={false}
                  dataKey='y'
                  stroke={borderColor}
                  onClick={(data, e) => {
                    console.log(data)
                    setIndex(e.target)
                  }}
                  onMouseDown={(data, e) => {
                    console.log(data, e)
                  }}
                  strokeWidth={2} />
                {(referenceLine || {}).y &&
                <ReferenceLine
                  y={referenceLine.y}
                  label={referenceLine.label}
                  stroke={referenceLine.color} />}
              </LineChart>
            </ResponsiveContainer>}
        </div>
      </div>
    </div>
  )
}

const enhance = compose(
  withState('index', 'setIndex', null)
)

export default enhance(Analytics)
