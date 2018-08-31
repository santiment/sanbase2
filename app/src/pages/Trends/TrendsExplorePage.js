import React from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import TrendsExploreChart from '../../components/Trends/Explore/TrendsExploreChart'
import './TrendsExplorePage.css'
import TrendsExploreTimeFilter from '../../components/Trends/Explore/TrendsExploreTimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'

const TrendsExplorePage = ({ data: { topicSearch = {} }, match }) => {
  return (
    <div className='TrendsExplorePage'>
      <div className='TrendsExplorePage__content'>
        <TrendsExploreHeader topic={match.params.topic} />
        <TrendsExploreTimeFilter selectedOption='6m' />

        <TrendsExploreChart data={topicSearch.chartsData || {}} />
      </div>
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
