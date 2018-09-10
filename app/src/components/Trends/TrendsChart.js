import React, { Fragment } from 'react'
import PropTypes from 'prop-types'
import 'chartjs-plugin-annotation'
import { Line } from 'react-chartjs-2'
import { mergeDataSourcesForChart, SourceColor } from './trendsUtils'

const createDatasetOptions = (label, borderColor) => ({
  label,
  yAxisID: 'y-axis-0',
  borderColor,
  backgroundColor: borderColor,
  borderWidth: 0.8,
  pointRadius: 0,
  pointHoverRadius: 2,
  fill: false
})

const chartDatasetOptions = {
  merged: createDatasetOptions('Merged', SourceColor['merged']),
  telegram: createDatasetOptions('Telegram', SourceColor['telegram']),
  reddit: createDatasetOptions('Reddit', SourceColor['reddit']),
  professional_traders_chat: createDatasetOptions(
    'Professional Traders Chat',
    SourceColor['professionalTradersChat']
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

  return selectedSources.map(selectedSource => ({
    data: sources[selectedSource]
      ? sources[selectedSource].map(item => item.mentionsCount)
      : [],
    ...chartDatasetOptions[selectedSource]
  }))
}

const propTypes = {
  sources: PropTypes.object.isRequired,
  selectedSources: PropTypes.array.isRequired,
  chartOptions: PropTypes.object.isRequired
}

const TrendsChart = ({
  sources,
  isLoading,
  selectedSources,
  chartOptions,
  isDesktop = true,
  ...props
}) => {
  const mergedSources = mergeDataSourcesForChart(sources)

  const dataset = {
    labels: [...mergedSources.keys()],
    datasets: composeSourcesChartDatasets(sources, selectedSources)
  }

  return (
    <Fragment>
      {isLoading && <div className='chart-loading-msg'>Loading...</div>}
      <Line
        options={chartOptions}
        data={dataset}
        height={isDesktop ? 80 : 200}
        {...props}
      />
    </Fragment>
  )
}

TrendsChart.propTypes = propTypes

export default TrendsChart
