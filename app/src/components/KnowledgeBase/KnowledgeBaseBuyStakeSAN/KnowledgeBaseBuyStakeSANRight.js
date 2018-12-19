import React from 'react'
import styles from './KnowledgeBaseBuyStakeSANRight.module.scss'

const KnowledgeBaseBuyStakeSANRight = () => {
  return (
    <div className={styles.content}>
      <h3 className={styles.title}>
        “Staking” means holding a certain number of tokens at an ETH address
        that SANbase can check each time you visit (it’s a lot like maintaining
        a minimum balance in a bank account).
      </h3>
      <p className={styles.text}>
        SANbase performs this check with the help of Metamask, a browser plugin
        that interfaces directly with the Ethereum blockchain.
      </p>
      <p className={styles.text}>
        If you’re logged into Metamask, SANbase can detect the number of tokens
        at your address and then give you access to advanced features, such as:
      </p>
      <h4 className={styles.subtitle}>SANbase Dashboards (200 SAN)</h4>
      <p className={styles.text}>
        Advanced beta visualizations and experimental data feeds
      </p>
      <h4 className={styles.subtitle}>Sentiment feed (1000 SAN)</h4>
      <p className={styles.text}>
        Custom metric based on aggregated social data, plotted against asset
        price
      </p>
      <h4 className={styles.subtitle}>Historical/Real-time API (1000 SAN)</h4>
      <p className={styles.text}>
        Full historical data beyond 3 months, plus real-time data feed
      </p>
      <p className={styles.text}>
        See the detailed{' '}
        <a href='https://app.santiment.net/price-list'>Price List</a> for more
        information.
      </p>
    </div>
  )
}

export default KnowledgeBaseBuyStakeSANRight
