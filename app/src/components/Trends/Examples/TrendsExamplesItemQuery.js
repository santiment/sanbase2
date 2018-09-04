import React from 'react'
import './TrendsExamplesItemQuery.css'

const TrendsExamplesItemQuery = ({ topic, fontSize = '2em' }) => {
  return (
    <div className='TrendsExamplesItemQuery' style={{ fontSize }}>
      <span>{topic}</span>
    </div>
  )
}

export default TrendsExamplesItemQuery
