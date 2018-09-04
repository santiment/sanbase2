import React, { Fragment } from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { Line } from 'react-chartjs-2'
import { trendsExploreGQL } from '../trendsExploreGQL'
import { mergeDataSourcesForChart, parseTrendsGQLProps } from '../trendsUtils'
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

const TrendsExamplesItemChart = ({ sources }) => {
  const isLoading = !sources

  const mergedSources = mergeDataSourcesForChart(sources)

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
