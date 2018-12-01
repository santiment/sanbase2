import React from 'react'
import styles from './DesktopProfileMenu.module.css'
import { HashLink as Link } from 'react-router-hash-link'

export const DesktopKnowledgeBaseMenu = () => (
  <div className={styles.wrapper}>
    <Link className={styles.button} to='/guide#get-started'>
      Get Started
    </Link>
    <Link className={styles.button} to='/guide#metrics'>
      Metrics We Offer
    </Link>
    <Link className={styles.button} to='/guide#buy-stake-san'>
      Buy &amp; Stake SAN
    </Link>
    <Link className={styles.button} to='/guide#price-list'>
      Price List
    </Link>
    <Link className={styles.button} to='/roadmap'>
      Roadmap
    </Link>
    <Link className={styles.button} to='/guide#support'>
      Support
    </Link>
  </div>
)

export default DesktopKnowledgeBaseMenu
