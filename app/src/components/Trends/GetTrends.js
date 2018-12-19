import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import moment from 'moment'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import { getTimeFromFromString } from './../../utils/utils'

const GetTrends = ({ render, sources = {}, ...props }) =>
  render({ sources, ...props })

const emptyChartData = []

export const normalizeTopic = topic => {
  const pattern = /AND|OR/
  if (topic.split(' ').length > 1 && !pattern.test(topic)) {
    return `"${topic}"`
  }
  return topic
}

const parseTrendsGQLProps = sourceType => ({
  data: { loading, error, topicSearch = {} },
  ownProps: { sources = {} }
}) => {
  const { chartData = emptyChartData } = topicSearch
  return {
    sources: {
      ...sources,
      [`${sourceType.toLowerCase()}`]: chartData
    },
    isLoading: loading,
    isError: error
  }
}

const makeAllQueries = () =>
  ['TELEGRAM', 'PROFESSIONAL_TRADERS_CHAT', 'REDDIT'].map(source =>
    graphql(trendsExploreGQL, {
      props: parseTrendsGQLProps(source),
      options: ({ topic, timeRange }) => ({
        variables: {
          searchText: normalizeTopic(topic),
          source: source,
          to: moment().toISOString(),
          from: getTimeFromFromString(timeRange)
        }
      })
    })
  )

export default compose(...makeAllQueries())(GetTrends)
