import React from 'react'
import { Helmet } from 'react-helmet'
import TrendsSearch from '../../components/Trends/TrendsSearch'
import GetHypedTrends from './../../components/Trends/GetHypedTrends'
import HypedBlocks from './../../components/Trends/HypedBlocks'
import styles from './TrendsPage.module.scss'

const TrendsPage = ({ isDesktop = true }) => (
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
      render={({ isLoading, items }) => (
        <HypedBlocks
          items={items}
          isLoading={isLoading}
          isDesktop={isDesktop}
        />
      )}
    />
  </div>
)

export default TrendsPage
