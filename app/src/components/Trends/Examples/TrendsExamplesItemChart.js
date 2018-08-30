import React from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { Line } from 'react-chartjs-2'
import { trendsExploreGQL } from '../trendsExploreGQL'
import { mergeDataSourcesForChart } from '../trendsUtils'

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
      // hoverRadius: 5,
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

const TrendsExamplesItemChart = ({
  data: { topicSearch = { chartsData: {} } }
}) => {
  const isLoading = Object.keys(topicSearch.chartsData).length === 0

  const mergedSources = mergeDataSourcesForChart(topicSearch.chartsData)

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
    <div>
      {isLoading && <div className='chart-loading-msg'>Loading...</div>}
      <Line options={chartOptions} data={dataset} />
    </div>
  )
}

export default graphql(trendsExploreGQL, {
  options: ({ query }) => {
    return {
      variables: {
        searchText: query,
        from: moment()
          .utc()
          .subtract(7, 'days')
          .format()
      }
    }
  }
})(TrendsExamplesItemChart)
