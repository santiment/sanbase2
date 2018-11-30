import React from 'react'
import { Helmet } from 'react-helmet'
import TrendsSearch from '../../components/Trends/TrendsSearch'
import GetHypedTrends from './../../components/Trends/GetHypedTrends'
import HypedWordsBlock from './../../components/Trends/HypedWordsBlock'
import styles from './TrendsPage.module.scss'

const TrendsPage = () => (
  <div className={styles.TrendsPage + ' page'}>
    <Helmet>
      <style>{'body { background-color: white; }'}</style>
    </Helmet>
    <div className={styles.header}>
      <h1>
        Explore frequently-used <br />
        words in crypto social media
      </h1>
      <TrendsSearch />
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
