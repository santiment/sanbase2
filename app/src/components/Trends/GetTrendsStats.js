import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { getStartOfTheDay, getTimeFromFromString } from './../../utils/utils'

export const trendsStatsExploreGQL = gql`
  query elasticsearchStats($from: DateTime!, $to: DateTime!) {
    elasticsearchStats(from: $from, to: $to) {
      documentsCount
      telegramChannelsCount
      subredditsCount
      sizeInMegabytes
      averageDocumentsPerDay
    }
  }
`

const GetTrendsStats = ({ render, ...props }) => render(props)

const makeProps = () => ({
  data: { loading, error, elasticsearchStats = {} }
}) => {
  return {
    stats: elasticsearchStats,
    isLoading: loading,
    isError: error
  }
}

export default graphql(trendsStatsExploreGQL, {
  props: makeProps(),
  options: ({ timeRange }) => ({
    variables: {
      to: getStartOfTheDay(),
      from: getTimeFromFromString(timeRange)
    }
  })
})(GetTrendsStats)
