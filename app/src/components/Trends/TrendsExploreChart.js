import React from 'react'
import moment from 'moment'
import 'chartjs-plugin-annotation'
import { Line } from 'react-chartjs-2'
import { mergeDataSourcesForChart } from './trendsUtils'
import './TrendsExploreChart.css'

const chartOptions = {
  animation: false,
  legend: {
    display: false
  },
  scales: {
    yAxes: [
      {
        // display: false
      }
    ],
    xAxes: [
      {
        ticks: {
          // Include a dollar sign in the ticks
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
      hoverRadius: 5,
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
        return moment(item[0].xLabel)
          .utc()
          .format('MMM DD YYYY')
      }
    }
  }
}

const datasetOptions = {
  borderColor: 'rgba(255, 193, 7, 1)',
  borderWidth: 1,
  pointRadius: 0,
  fill: false
}

const TrendsExploreChart = ({ data }) => {
  console.log('TCL: TrendsExploreChart -> data', data)

  const isLoading = Object.keys(data).length === 0

  const mergedSources = mergeDataSourcesForChart(data)

  const dataset = {
    labels: [...mergedSources.keys()],
    datasets: [
      {
        data: [...mergedSources.values()],
        ...datasetOptions
      }
    ]
  }
  return (
    <div className='TrendsExploreChart'>
      {isLoading && <div className='chart-loading-msg'>Loading...</div>}
      <Line options={chartOptions} data={dataset} />
    </div>
  )
}

export default TrendsExploreChart
