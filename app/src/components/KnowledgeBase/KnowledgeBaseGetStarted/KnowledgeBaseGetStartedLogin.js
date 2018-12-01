import React from 'react'
import styles from '../KnowledgeBaseGetStarted.module.scss'

const KnowledgeBaseGetStartedLogin = () => {
  return (
    <>
      <h4 className={styles.title} id='logging'>
        Logging In
      </h4>
      <p className={styles.text}>
        Santiment offers two ways to log in: with an email address, and with a
        Metamask account.
      </p>

      <h5 className={styles.subtitle}>Login with Email </h5>
      <p className={styles.text}>
        The benefit of using an email address to log in is, you have access to
        other features in SANbase as well as expanded data.
      </p>
      <ul>
        <li>Read, write, and share Insights </li>
        <li>Create Watchlists (custom lists of assets) </li>
      </ul>

      <h5 className={styles.subtitle}>Log in with Metamask</h5>
      <p className={styles.text}>
        You get everything with an email login, plus access to SANbase
        Dashboards and additional features depending on staking level
      </p>
    </>
  )
}

export default KnowledgeBaseGetStartedLogin
