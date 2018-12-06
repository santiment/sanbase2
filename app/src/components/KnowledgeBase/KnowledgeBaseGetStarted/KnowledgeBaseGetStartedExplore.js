import React from 'react'
import styles from '../KnowledgeBaseGetStarted.module.scss'

const KnowledgeBaseGetStartedExplore = () => {
  return (
    <>
      <h4 className={styles.title} id='explore'>
        Explore for Free
      </h4>
      <p className={styles.text}>
        Many parts of SANbase are usable for free, without logging in.
      </p>
      <p className={styles.text}>
        One is the ASSETS section, where you can see lists of assets that have
        data in SANbase.
      </p>
      <p className={styles.text}>
        <strong>Sort lists by columns</strong> to compare spot trends:
      </p>
      <p className={styles.text}>
        <strong>Click assets to see metrics</strong> plotted against price, and
        other fundamental info:
      </p>
      <p className={styles.text}>
        Another is ETH SPENT, which has been useful for spotting when ERC20
        projects move their ETH reserves. Click the ETH Spent list in the ASSETS
        section, then scroll down (you’ll be on the Ethereum page) to the
        Ethereum Spent Overview, where you can sort by columns and find links to
        project wallets.
      </p>
      <img
        src='https://lh5.googleusercontent.com/F_nmhJIf1pj-btEM8pXPdMigEdAkvZU2lZjdyktLJTIl07DGGoPDKH9mQauFMQHXz4weN3vySlvAT1zHzgl5KSHGQB41H_YE_RaFFaIHPVlHhbj-ENKeQMLwkQ82iyGSEwG6YbR4'
        alt='Eth spent'
        className={styles.img}
      />
      <p className={styles.text}>
        Here are a couple of uses of these tools in action
      </p>
      <ul>
        <li>Case 1 (tbd)</li>
        <li>Case 2 (tbd)</li>
      </ul>
    </>
  )
}

export default KnowledgeBaseGetStartedExplore
