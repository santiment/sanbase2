import React from 'react'
import { Link } from 'react-router-dom'
import styles from './WatchlistsAnon.module.css'

const WatchlistsAnon = () => (
  <div className={styles.wrapper}>
    Use Watchlist to organize and track assets you're interested in.
    <h5 className={styles.msg}>
      You'll need to <Link to='/login'>log in</Link> to use this feature.
    </h5>
  </div>
)

export default WatchlistsAnon
