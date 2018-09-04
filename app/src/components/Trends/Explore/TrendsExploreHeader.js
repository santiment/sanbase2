import React from 'react'
import './TrendsExploreHeader.css'
import TrendsExamplesItemQuery from '../Examples/TrendsExamplesItemQuery'

const TrendsExploreHeader = ({ topic }) => {
  return (
    <div className='TrendsExploreHeader'>
      <div className='TrendsExploreHeaderTitles'>
        <div className='TrendsExploreHeaderTitles__item'>
          <TrendsExamplesItemQuery topic={topic} />
        </div>
      </div>
    </div>
  )
}

export default TrendsExploreHeader
