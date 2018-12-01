import React from 'react'
import styles from '../KnowledgeBaseGetStarted.module.scss'

const KnowledgeBaseGetStartedMetrics = () => {
  return (
    <>
      <h4 className={styles.title} id='metrics'>
        Metrics We Offer
      </h4>
      <p className={styles.text}>
        Santiment brings a comprehensive set of metrics together in one place so
        you can get a better picture of what’s happening with your favorite
        crypto assets and/or crypto markets in general. We emphasize plotting
        metrics against price over time, to more easily spot how trends and
        events correlate with price action.
      </p>
      <p className={styles.text}>Major types of metrics include:</p>

      <h5 className={styles.subtitle}>Financial</h5>
      <p className={styles.text}>
        Traditional fundamentals including price, volume and market cap, plus
        crypto-related data like total supply, circulating supply, top
        transactions and ROI since ICO (if applicable)
      </p>

      <h5 className={styles.subtitle}>Development</h5>
      <p className={styles.text}>
        Custom Github metric we created to accurately measure a team’s
        development activity.
      </p>
      <h5 className={styles.subtitle}>On-chain</h5>
      <p className={styles.text}>
        Metrics taken directly from various blockchains (BTC, ETH/ERC20, EOS and
        growing), including transaction volume, daily active addresses, exchange
        flow and more.
      </p>
      <h5 className={styles.subtitle}>Social/Sentiment</h5>
      <p className={styles.text}>
        Metrics taken from measuring social activity on crypto-related forums
        and channels, plus custom sentiment measurements analyzing crowd
        behavior.
      </p>
      <p className={styles.text}>
        See our <a href='https://app.santiment.net/metrics'>Metrics List</a> for
        a complete list with definitions and metric types. <br />
        See our <a href='https://app.santiment.net/price-list'>
          Price List
        </a>{' '}
        for more details about accessing the data (some metrics are available
        for specific timeframes and staking levels).
      </p>
    </>
  )
}

export default KnowledgeBaseGetStartedMetrics
