import React from 'react'
import './TrendsExploreHeader.css'
import TrendsExamplesItemQuery from '../Examples/TrendsExamplesItemQuery'
import TrendsExploreHeaderCompareNew from './TrendsExploreHeaderCompareNew'
/*
borderImage: `linear-gradient(to right, red 33%, green 33%, green 66%, blue 66%)`;
borderImageSlice: `0% 0% 3%`;
borderStyle: `solid`;
 */
const TrendsExploreHeader = ({ topic }) => {
  return (
    <div className='TrendsExploreHeader'>
      <div className='TrendsExploreHeaderTitles'>
        <div className='TrendsExploreHeaderTitles__item'>
          <TrendsExamplesItemQuery fontSize='2em' query={topic} />
        </div>
        {/* <TrendsExploreHeaderCompareNew /> */}
      </div>
    </div>
  )
}

export default TrendsExploreHeader
