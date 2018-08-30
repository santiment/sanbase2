import React from 'react'
import TrendsExamplesItemIcon from './TrendsExamplesItemIcon'
import './TrendsExamplesItemQuery.css'

const TrendsExamplesItemQuery = ({ query }) => {
  return (
    <div className='TrendsExamplesItemQuery'>
      {/* <TrendsExamplesItemIcon name='search' /> */}
      <span>{query}</span>
    </div>
  )
}

export default TrendsExamplesItemQuery
