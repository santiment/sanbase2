import React from 'react'
import { Link } from 'react-router-dom'
import styles from './DesktopProfileMenu.module.css'
import DesktopWatchlistSubmenu from './DesktopWatchlistSubmenu'

export const DesktopAssetsMenu = () => (
  <div className={styles.wrapper}>
    <h3>Default</h3>
    <Link className={styles.button} to='/assets/all'>
      All Assets
    </Link>
    <Link className={styles.button} to='/assets/erc20'>
      ERC 20
    </Link>
    <Link className={styles.button} to='/projects/ethereum'>
      ETH Spent
    </Link>

    <DesktopWatchlistSubmenu />
  </div>
)

export default DesktopAssetsMenu
