import React from 'react'
import './TrendsExamplesItemTopic.css'

import { composeBorderBottomGradient } from '../trendsUtils'

const TrendsExamplesItemTopic = ({
  topic,
  selectedSources,
  fontSize = '2em'
}) => {
  console.log(composeBorderBottomGradient(selectedSources))
  return (
    <div className='TrendsExamplesItemTopic' style={{ fontSize }}>
      <span>
        {topic}
        <div
          className='TrendsExamplesItemTopic__underline'
          style={{ background: composeBorderBottomGradient(selectedSources) }}
        />
      </span>
    </div>
  )
}

export default TrendsExamplesItemTopic
