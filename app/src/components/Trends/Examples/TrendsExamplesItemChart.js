import React from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { trendsExploreGQL } from '../trendsExploreGQL'
import { parseTrendsGQLProps } from '../trendsUtils'
import TrendsChart from '../TrendsChart'

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

const TrendsExamplesItemChart = ({ sources, selectedSources }) => {
  return (
    <TrendsChart
      sources={sources}
      selectedSources={selectedSources}
      chartOptions={chartOptions}
      height={null}
    />
  )
}

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
