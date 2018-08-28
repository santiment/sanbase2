import React from 'react'
import { graphql } from 'react-apollo'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import TrendsExploreChart from '../../components/Trends/TrendsExploreChart'

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
        searchText: match.params.topic
      }
    }
  }
})(TrendsExplorePage)
