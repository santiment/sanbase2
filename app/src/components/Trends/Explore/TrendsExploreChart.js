import React from 'react'
import 'chartjs-plugin-annotation'
import TrendsChart from '../TrendsChart'
import moment from 'moment'
import './TrendsExploreChart.css'

const chartOptions = {
  responsive: true,
  scaleFontSize: 0,
  animation: false,
  legend: {
    display: false
  },
  scales: {
    yAxes: [
      {
        id: 'y-axis-0',
        ticks: {
          autoSkip: true,
          maxTicksLimit: 5,
          callback: item => (item !== 0 ? item : '')
        }
      }
    ],
    xAxes: [
      {
        gridLines: {
          display: false
        },
        ticks: {
          autoSkip: true,
          maxTicksLimit: 4,
          maxRotation: 0,
          callback: date =>
            moment(date)
              .utc()
              .format('DD MMM YY')
        }
      }
    ]
  },
  elements: {
    point: {
      hitRadius: 5,
      hoverRadius: 0.5,
      radius: 0
    },
    line: {
      tension: 0.2
    }
  },
  tooltips: {
    mode: 'x',
    intersect: false,
    titleMarginBottom: 10,
    titleFontSize: 13,
    titleFontColor: '#3d4450',
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    cornerRadius: 3,
    borderColor: 'rgba(38, 43, 51, 0.7)',
    borderWidth: 1,
    bodyFontSize: 12,
    bodySpacing: 8,
    bodyFontColor: '#3d4450',
    displayColors: true,
    callbacks: {
      title: item => {
        return moment(item[0].xLabel)
          .utc()
          .format('MMM DD YYYY')
      },
      label: (tooltipItem, data) => {
        const label = data.datasets[tooltipItem.datasetIndex].label.toString()
        return `${label} Mentions: ${tooltipItem.yLabel}`
      }
    }
  }
}

const TrendsExploreChart = props => (
  <div className='TrendsExploreChart'>
    <TrendsChart {...props} chartOptions={chartOptions} />
  </div>
)

export default TrendsExploreChart
