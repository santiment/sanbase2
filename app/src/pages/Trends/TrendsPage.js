import React from 'react'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'
import TrendsExamplesItemTopic from '../../components/Trends/Examples/TrendsExamplesItemTopic'
import './TrendsPage.css'

const TrendsPage = () => (
  <div className='TrendsPage page'>
    <h1 className='TrendsPage__title'>
      See how often a crypto term is mentioned in social media
    </h1>
    <TrendsExamplesItemTopic />
    <TrendsExamples />
  </div>
)

export default TrendsPage
