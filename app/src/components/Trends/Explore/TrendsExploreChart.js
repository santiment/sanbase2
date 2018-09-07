import React from 'react'
import moment from 'moment'
import 'chartjs-plugin-annotation'
import { Line } from 'react-chartjs-2'
import { mergeDataSourcesForChart } from '../trendsUtils'
import './TrendsExploreChart.css'

const chartOptions = {
  responsive: true,
  scaleFontSize: 0,
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
          callback: (item, index) => (item !== 0 ? item : '')
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

const createDatasetOptions = (label, borderColor) => ({
  label,
  yAxisID: 'y-axis-0',
  borderColor,
  borderWidth: 0,
  pointRadius: 0,
  fill: false
})

const chartDatasetOptions = {
  merged: createDatasetOptions('Merged', 'rgb(255, 193, 7)'),
  telegram: createDatasetOptions('Telegram', 'rgb(0, 0, 255)'),
  reddit: createDatasetOptions('Reddit', 'rgb(255, 0, 0)'),
  professionalTradersChat: createDatasetOptions(
    'Professional Traders Chat',
    'rgb(255, 0, 255)'
  )
}

const composeSourcesChartDatasets = (sources, selectedSources) => {
  if (selectedSources.includes('merged')) {
    return [
      {
        data: [...mergeDataSourcesForChart(sources).values()],
        ...chartDatasetOptions['merged']
      }
    ]
  }
  // AS ternary
  return selectedSources.map(selectedSource => ({
    data:
      sources[selectedSource] &&
      sources[selectedSource].map(item => item.mentionsCount),
    ...chartDatasetOptions[selectedSource]
  }))
}

const TrendsExploreChart = ({ sources, selectedSources, isDesktop }) => {
  console.log('TCL: TrendsExploreChart -> selectedSources', selectedSources)
  const isLoading = !sources

  const mergedSources = mergeDataSourcesForChart(sources)

  const dataset = {
    labels: [...mergedSources.keys()],
    datasets: composeSourcesChartDatasets(sources, selectedSources)
  }
  return (
    <div className='TrendsExploreChart'>
      {isLoading && <div className='chart-loading-msg'>Loading...</div>}
      <Line
        options={chartOptions}
        data={dataset}
        height={isDesktop ? 80 : 200}
      />
    </div>
  )
}

export default TrendsExploreChart
