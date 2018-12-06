import React from 'react'
import styles from '../KnowledgeBaseGetStarted.module.scss'

const KnowledgeBaseGetStartedParts = () => {
  return (
    <>
      <h4 className={styles.title} id='parts'>
        Parts of SANbase
      </h4>
      <p className={styles.text}>
        There are a few ways you can access Santiment tools and data.
      </p>
      <h5 className={styles.subtitle}>SANbase</h5>
      <p className={styles.text}>
        SANbase is our main blockchain-enabled web app, which is also accessible
        on mobile. It provides financial, development, on-chain and
        social/sentiment data for the general crypto market plus more than 1500
        crypto assets across a growing number of blockchains.
      </p>
      <p className={styles.text}>
        Much of the data is available anonymously, for free. Get more in-depth
        features with a simple email login. <br />
        <a href='https://app.santiment.net'>https://app.santiment.net</a>
      </p>
      <img
        src='https://lh5.googleusercontent.com/TCo_oammD2F1aI8YmxCECYrIgNGesWeVoy1GnruBFO1t-kDc2qph0p3xxdWYbjL-VVSR8B5IF5F6xfjp3I7FVHYesBfulqEXPjS0ljUhswQXP5T9OrNrpafBTCSyKJYJKoDJBjda'
        alt='App index'
        className={styles.img}
      />
      <h5 className={styles.subtitle}>SANbase Dashboards</h5>
      <p className={styles.text}>
        SANbase Dashboards is our beta test area, where we have experimental
        features and work out new datafeeds before introducing them to SANbase.
        This area is accessible via SAN staking and is for more advanced users.{' '}
        <br />
        <a href='https://data.santiment.net'>https://data.santiment.net</a>
        <img
          src='https://lh3.googleusercontent.com/En4_HMOI-_7nmCq-VQmfRBBycGsL9YJ9HdN9lTEDVkk-uJ5ZS_IjRd4j8CUY1sQEV6jnuMUT3XuP-aQrnlnnAoffxMH44ODIbceuY2KeJ7gw2kW_V9N82UEEp3tsPr0tvAPkrBSv'
          alt='Data santiment'
          className={styles.img}
        />
      </p>
      <h5 className={styles.subtitle}>SANbase API</h5>
      <p className={styles.text}>
        Use it free for 3 months of data, or stake SAN for full historical data
        plus real time data feed. <br />
        <a href='https://docs.santiment.net'>https://docs.santiment.net</a>
        <img
          src='https://lh3.googleusercontent.com/zciX_UQGgWwJLV3CLzCTY4YzfviDpX60hniI8ai9ilWpwjVmY4II1WwDZwFpHS7y5zah7m-1C8tVQC1Zs4IwwKU71HcAQ13AO0bLduL2QE1wdkpI25GQLTXXcXQM8n1A7VF1gtgy'
          alt='SANbase API'
          className={styles.img}
        />
      </p>
      <h5 className={styles.subtitle}>SANbase Sheets</h5>
      <p className={styles.text}>
        SANbase Sheets is a plugin for Google or Excel spreadsheets. Transform
        your sheets with select crypto metrics for the past 3 months. You can
        find the plugin under the Add-Ons menu (Get Add-Ons > Search for
        Santiment).
      </p>
      <img
        src='https://lh5.googleusercontent.com/UOF4BBCd7JBLjvXGCN6tTE__oHwwXIgEC2ir55f2lABmnF7aDRRl4CwSaTxO5VI1BXFmih-ejZ9kBFbvKmq1wdJOWwkUpqIAZcqeAy0Tj8OFmMx1Bv0RFAwNEoAWBWnuAZck6b7e'
        alt='SANbase Sheets'
        className={styles.img}
      />
      <p className={styles.text}>
        For a detailed breakdown of which metrics are included, see the{' '}
        <a href='https://app.santiment.net/price-list'>Price List</a>
      </p>
    </>
  )
}

export default KnowledgeBaseGetStartedParts
