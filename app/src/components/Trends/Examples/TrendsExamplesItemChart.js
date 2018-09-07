import React, { Fragment } from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { Line } from 'react-chartjs-2'
import { trendsExploreGQL } from '../trendsExploreGQL'
import {
  mergeDataSourcesForChart,
  parseTrendsGQLProps,
  SourceColor
} from '../trendsUtils'
import PropTypes from 'prop-types'

const chartOptions = {
  animation: false,
  legend: {
    display: false
  },
  scales: {
    yAxes: [
      {
        display: false
      }
    ],
    xAxes: [
      {
        display: false
      }
    ]
  },
  elements: {
    point: {
      hitRadius: 0,
      radius: 0
    }
  }
}

const datasetOptions = {
  borderColor: 'rgba(255, 193, 7, 1)',
  borderWidth: 2,
  pointRadius: 0,
  fill: false
}

const propTypes = {
  sources: PropTypes.object.isRequired,
  topic: PropTypes.string.isRequired
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
  merged: createDatasetOptions('Merged', SourceColor['merged']),
  telegram: createDatasetOptions('Telegram', SourceColor['telegram']),
  reddit: createDatasetOptions('Reddit', SourceColor['reddit']),
  professionalTradersChat: createDatasetOptions(
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
  // AS ternary
  return selectedSources.map(selectedSource => ({
    data:
      sources[selectedSource] &&
      sources[selectedSource].map(item => item.mentionsCount),
    ...chartDatasetOptions[selectedSource]
  }))
}

const TrendsExamplesItemChart = ({ sources, selectedSources }) => {
  const isLoading = !sources

  const mergedSources = mergeDataSourcesForChart(sources)

  const dataset = {
    labels: [...mergedSources.keys()],
    datasets: composeSourcesChartDatasets(sources, selectedSources)
  }

  return (
    <Fragment>
      {isLoading && <div className='chart-loading-msg'>Loading...</div>}
      <Line options={chartOptions} data={dataset} />
    </Fragment>
  )
}

TrendsExamplesItemChart.propTypes = propTypes

export default graphql(trendsExploreGQL, {
  props: parseTrendsGQLProps,
  options: ({ topic }) => {
    return {
      variables: {
        searchText: topic,
        from: moment()
          .utc()
          .subtract(7, 'days')
          .format()
      }
    }
  }
})(TrendsExamplesItemChart)
