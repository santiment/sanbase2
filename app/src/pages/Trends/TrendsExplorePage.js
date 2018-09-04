import React from 'react'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import TrendsExploreChart from '../../components/Trends/Explore/TrendsExploreChart'
import './TrendsExplorePage.css'
import TimeFilter from './../../components/TimeFilter/TimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
import TrendsExploreFooter from '../../components/Trends/Explore/TrendsExploreFooter'
import { parseTrendsGQLProps } from '../../components/Trends/trendsUtils'

const TrendsExplorePage = ({ sources, match, isDesktop }) => {
  return (
    <div className='TrendsExplorePage'>
      <div className='TrendsExplorePage__content'>
        <TrendsExploreHeader topic={match.params.topic} />
        <TimeFilter
          timeOptions={['1w', '1m', '3m', '6m', '1y', 'all']}
          defaultSelected='6m'
          disabled
        />
        <TrendsExploreChart sources={sources} isDesktop={isDesktop} />
        <TrendsExploreFooter />
      </div>
    </div>
  )
}

export default graphql(trendsExploreGQL, {
  props: parseTrendsGQLProps,
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
