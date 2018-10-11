import React from 'react'
import './TrendsExploreHeader.css'
import TrendsExamplesItemTopic from '../Examples/TrendsExamplesItemTopic'

const TrendsExploreHeader = ({ topic }) => {
  return (
    <div className='TrendsExploreHeader'>
      <div className='TrendsExploreHeaderTitles'>
        <div className='TrendsExploreHeaderTitles__item'>
          <TrendsExamplesItemTopic topic={topic} />
        </div>
      </div>
    </div>
  )
}

export default TrendsExploreHeader
