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
        [`${label}`]: +data[`${label}`]
      })) : [],
      datalabels: {
        display: false
      }
    }]
  }
}

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
  const tooltip = (
    <Tooltip
      formatter={formatData}
      labelFormatter={index => {
        const datetime = chartData.datasets[0].data[index].x
        return moment(datetime).format('DD.MM.YYYY')
      }}
      label={'asdf'}
    />)
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
                {tooltip}
                <Bar dataKey={label} stroke={borderColor} fill={borderColor} />
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
                syncId={syncId}
                dot={false}
                data={chartData.datasets[0].data} >
                {tooltip}
                <Line
                  type='monotone'
                  dot={false}
                  dataKey={label}
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
