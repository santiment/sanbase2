import React from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import TrendsExploreChart from '../../components/Trends/Explore/TrendsExploreChart'

const TrendsExplorePage = ({ data: { topicSearch = {} } }) => {
  return (
    <div>
      <TrendsExploreChart data={topicSearch.chartsData || {}} />
    </div>
  )
}

export default graphql(trendsExploreGQL, {
  options: ({ match }) => {
    return {
      variables: {
        searchText: match.params.topic,
        from: moment()
          .utc()
          .subtract(6, 'months')
          .format()
      }
    }
  }
})(TrendsExplorePage)
