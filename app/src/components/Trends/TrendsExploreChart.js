import React from 'react'
import moment from 'moment'
import 'chartjs-plugin-annotation'
import { Line } from 'react-chartjs-2'
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
        id: 'x-axis-0'
        // display: false
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
        return moment(item[0].xLabel).format('MMM DD YYYY')
      }
      //   label: tooltipItem =>
      //     formatNumber(tooltipItem.yLabel, {
      //       currency: 'USD'
      //     })
    }
  }
}

const datasetOptions = {
  borderColor: 'rgba(255, 193, 7, 1)',
  borderWidth: 1,
  pointRadius: 0,
  fill: false
}

const mergeSources = sources =>
  Object.keys(sources).reduce((acc, source) => {
    for (const { datetime, mentionsCount } of sources[source]) {
      acc.set(datetime, mentionsCount + (acc.get(datetime) || 0))
    }
    return acc
  }, new Map())

const TrendsExploreChart = ({ data: { __typename, ...sources } }) => {
  if (!sources) return null

  const mergedSources = mergeSources(sources)

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
      <Line options={chartOptions} data={dataset} />
    </div>
  )
}

export default TrendsExploreChart
