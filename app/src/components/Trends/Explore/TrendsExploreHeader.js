import React from 'react'
import './TrendsExploreHeader.css'
import TrendsExamplesItemQuery from '../Examples/TrendsExamplesItemQuery'

const TrendsExploreHeader = ({ topic }) => {
  return (
    <div className='TrendsExploreHeader'>
      <div className='TrendsExploreHeaderTitles'>
        <div className='TrendsExploreHeaderTitles__item'>
          <TrendsExamplesItemQuery fontSize='2em' query={topic} />
        </div>
        <div className='TrendsExploreHeaderCompareNew'>+ New comparison</div>
      </div>
      {/* <TrendsExploreHeaderCompareNew /> */}
    </div>
  )
}

export default TrendsExploreHeader
