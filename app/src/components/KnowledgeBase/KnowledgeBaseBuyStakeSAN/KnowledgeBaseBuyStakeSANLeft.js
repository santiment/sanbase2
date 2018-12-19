import React from 'react'
import styles from './KnowledgeBaseBuyStakeSANLeft.module.scss'

const KnowledgeBaseBuyStakeSANLeft = () => {
  return (
    <div className={styles.content}>
      <div className={styles.step}>
        <div className={styles.number}>1</div>
        <div className={styles.text}>
          <a href='https://metamask.io/'>Install Metamask</a> and create an ETH
          account (or attach an existing account).
        </div>
        <iframe
          src='https://www.youtube.com/embed/6Gf_kRE4MJU'
          frameBorder='0'
          allow='accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture'
          allowFullScreen
          className={styles.img}
        />
      </div>
      <div className={styles.step}>
        <div className={styles.number}>2</div>
        <div className={styles.text}>
          Get some ETH or BTC (can be purchased at an exchange using a currency
          of your choice).
          <img
            src='https://lh4.googleusercontent.com/Dd6N8wJrQ2lE-PHeOLYttnbLjqspDF5yTByYlZF1CHmQhdTLzPK7uW1BEVeCbCgRT6qs4c5BpF1hQBgcb8KdtVgUtyv5f_gNPyjx40oLsgiWRciH_ZtMIePrMwdRpAoY7uphENq4'
            alt='Currency choice'
            className={styles.img}
          />
        </div>
      </div>
      <div className={styles.step}>
        <div className={styles.number}>3</div>
        <div className={styles.text}>
          Sell ETH/BTC for SAN at an exchange listed here:{' '}
          <a href='https://coinmarketcap.com/currencies/santiment/#markets'>
            https://coinmarketcap.com/currencies/santiment/#markets
          </a>{' '}
        </div>
        <img
          src='https://lh4.googleusercontent.com/Cc8mYTTlA2OS5F0kEDtTEaVnRbYNkfpQ91c1TtwYWlL6HmJoDF3gNl_T5TylqN7Eo4ySqs-KQM4PIUs8HjWJcwB0z8XfpWoLQjI4xZJyj1TK4aCdQ47Y7MWlOfA3bZjJ2ISru7St'
          alt='Sell'
          className={styles.img}
        />
        <div className={styles.text}>
          SAN is also available at{' '}
          <a href='https://bitfinex.com/santiment'>Bitfinex</a> for ETH, BTC,
          and USD/USDT
        </div>
      </div>
      <div className={styles.step}>
        <div className={styles.number}>4</div>
        <div className={styles.text}>
          Transfer the SAN to the Metamask account you created in Step 1.
        </div>
        <img
          src='https://lh4.googleusercontent.com/ufMIJXaAyCqizjUbq9lGedh_BzVfLE7pQCTjNCy0b4XybvcX943dSOduy-6MU3KJmx0USkrheRLNqW7SGSyIOkWt4fkRjiJhdPR9ebe1q1Cyl9iyTTuQjWfNsaznMUGTTzPG4hz2'
          alt='Back to step 1'
          className={styles.img}
        />
        <div className={styles.text}>
          Then just be logged in to Metamask with that account selected when you
          visit SANbase. We’ll detect the SAN you’re staking there and grant you
          access.
        </div>
      </div>
    </div>
  )
}

export default KnowledgeBaseBuyStakeSANLeft
