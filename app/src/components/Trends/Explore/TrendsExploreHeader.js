import React from 'react'
import './TrendsExploreHeader.css'
import TrendsExamplesItemTopic from '../Examples/TrendsExamplesItemTopic'
import TrendsExploreShare from './TrendsExploreShare'

const TrendsExploreHeader = ({ topic }) => {
  return (
    <div className='TrendsExploreHeader'>
      <div className='TrendsExploreHeaderTitles'>
        <div className='TrendsExploreHeaderTitles__item'>
          <TrendsExamplesItemTopic topic={topic} />
          <TrendsExploreShare topic={topic} />
        </div>
      </div>
    </div>
  )
}

export default TrendsExploreHeader
