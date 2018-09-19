import React from 'react'
import TrendsForm from './../TrendsForm'
import './TrendsExamplesItemTopic.css'

const TrendsExamplesItemTopic = ({ topic, fontSize = '2em' }) => {
  return (
    <div className='TrendsExamplesItemTopic' style={{ fontSize }}>
      <TrendsForm defaultTopic={topic} />
    </div>
  )
}

export default TrendsExamplesItemTopic
