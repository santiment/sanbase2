import React from 'react'
import TrendsExamplesItemTopic from '../../components/Trends/Examples/TrendsExamplesItemTopic'
import TrendsTitle from '../../components/Trends/TrendsTitle'
import GetHypedTrends from './../../components/Trends/GetHypedTrends'
import HypedWordsBlock from './../../components/Trends/HypedWordsBlock'
import styles from './TrendsPage.module.css'
import './TrendsPage.scss'

const TrendsPage = () => (
  <div className='TrendsPage page'>
    <div className='TrendsPage__header'>
      <h1>Explore frequently-used words in crypto social media</h1>
      <TrendsExamplesItemTopic />
    </div>
    <GetHypedTrends
      render={({ isLoading, items }) => {
        if (isLoading) {
          return 'Loading...'
        }
        return (
          <div className={styles.HypedBlocks}>
            {items.map((hypedTrend, index) => (
              <HypedWordsBlock
                key={index}
                latest={index === items.length - 1}
                compiled={hypedTrend.datetime}
                trends={hypedTrend.topWords}
              />
            ))}
          </div>
        )
      }}
    />
  </div>
)

export default TrendsPage
