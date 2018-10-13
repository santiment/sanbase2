import React from 'react'
import TrendsForm from './../TrendsForm'
import HelpPopupTrends from './../../../pages/Trends/HelpPopupTrends'
import './TrendsExamplesItemTopic.css'

const TrendsExamplesItemTopic = ({ topic, fontSize = '1em' }) => {
  return (
    <div className='TrendsExamplesItemTopic' style={{ fontSize }}>
      <TrendsForm defaultTopic={topic} />
      <HelpPopupTrends className='TrendsExamplesItemTopic__help' />
    </div>
  )
}

export default TrendsExamplesItemTopic
