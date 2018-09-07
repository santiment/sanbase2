import React from 'react'
import './TrendsExamplesItemTopic.css'

const TrendsExamplesItemTopic = ({ topic, fontSize = '2em' }) => {
  return (
    <div className='TrendsExamplesItemTopic' style={{ fontSize }}>
      <span>{topic}</span>
    </div>
  )
}

export default TrendsExamplesItemTopic
