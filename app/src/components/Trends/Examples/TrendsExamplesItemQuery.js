import React from 'react'
import TrendsExamplesItemIcon from './TrendsExamplesItemIcon'
import './TrendsExamplesItemQuery.css'

const TrendsExamplesItemQuery = ({ query, fontSize }) => {
  return (
    <div className='TrendsExamplesItemQuery' style={fontSize && { fontSize }}>
      {/* <TrendsExamplesItemIcon name='search' /> */}
      <span>{query}</span>
    </div>
  )
}

export default TrendsExamplesItemQuery
