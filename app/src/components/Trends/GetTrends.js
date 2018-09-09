import moment from 'moment'
import { graphql } from 'react-apollo'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'

const GetTrends = ({ render, ...props }) => render(props)

const parseTrendsGQLProps = ({
  data: {
    loading,
    error,
    topicSearch = {
      chartsData: {}
    }
  }
}) => {
  const { __typename, ...sources } = topicSearch.chartsData
  return {
    sources,
    isLoading: loading,
    isError: error
  }
}

export default graphql(trendsExploreGQL, {
  props: parseTrendsGQLProps,
  options: ({ topic }) => ({
    variables: {
      searchText: topic,
      from: moment()
        .utc()
        .subtract(6, 'months')
        .format()
    }
  })
})(GetTrends)
