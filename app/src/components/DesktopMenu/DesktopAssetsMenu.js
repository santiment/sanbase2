import React from 'react'
import { Link } from 'react-router-dom'
import { withRouter } from 'react-router'
import styles from './DesktopProfileMenu.module.css'
import DesktopWatchlistSubmenu from './DesktopWatchlistSubmenu'

export const DesktopAssetsMenu = ({ location: { search } }) => (
  <div className={styles.wrapper}>
    <h3>Default</h3>
    <Link className={styles.button} to={{ pathname: '/assets/all', search }}>
      All Assets
    </Link>
    <Link className={styles.button} to={{ pathname: '/assets/erc20', search }}>
      ERC 20
    </Link>
    <Link className={styles.button} to='/projects/ethereum'>
      ETH Spent
    </Link>

    <DesktopWatchlistSubmenu />
  </div>
)

export default withRouter(DesktopAssetsMenu)
