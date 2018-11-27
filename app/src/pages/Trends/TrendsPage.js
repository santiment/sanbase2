import React from 'react'
import TrendsExamples from '../../components/Trends/Examples/TrendsExamples'
import TrendsExamplesItemTopic from '../../components/Trends/Examples/TrendsExamplesItemTopic'
import './TrendsPage.scss'
import TrendsTitle from '../../components/Trends/TrendsTitle'

const TrendsPage = () => (
  <div className='TrendsPage page'>
    <div className='TrendsPage__header'>
      <div>
        <TrendsTitle />
      </div>
      <div>
        <p>
          See how often a word or phrase is used in crypto social media, plotted
          against BTC or ETH price
        </p>
      </div>
    </div>
    <TrendsExamplesItemTopic />
    {/*
    <TrendsExamples />
    */}
  </div>
)

export default TrendsPage
