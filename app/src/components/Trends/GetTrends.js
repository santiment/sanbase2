import moment from 'moment'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'

const GetTrends = ({ render, sources = {}, ...props }) =>
  render({ sources, ...props })

const emptyChartData = []

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

const getStartOfTheDay = () => {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return today.toISOString()
}

const makeAllQueries = () =>
  ['TELEGRAM', 'PROFESSIONAL_TRADERS_CHAT', 'REDDIT'].map(source =>
    graphql(trendsExploreGQL, {
      props: parseTrendsGQLProps(source),
      skip: ({ selectedSources = [] }) => {
        return (
          !selectedSources.includes(source.toLocaleLowerCase()) &&
          selectedSources[0] !== 'merged'
        )
      },
      options: ({ topic }) => ({
        variables: {
          searchText: topic,
          source: source,
          to: getStartOfTheDay(),
          from: moment()
            .utc()
            .subtract(6, 'months')
            .format()
        }
      })
    })
  )

export default compose(...makeAllQueries())(GetTrends)
