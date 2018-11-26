import React from 'react'
import { Divider, Icon, Checkbox } from 'semantic-ui-react'
import cx from 'classnames'
import { HashLink as Link } from 'react-router-hash-link'
import styles from './DesktopProfileMenu.module.css'
import logo from './../../assets/logo.png'

const DesktopProfileMenu = ({
  balance = 0,
  toggleNightMode,
  toggleBetaMode,
  isNightModeEnabled,
  isBetaModeEnabled,
  logout
}) => (
  <div className={styles.wrapper}>
    <h3>Account</h3>
    <Link className={styles.button} to='/account'>
      <span>
        <Icon name='setting' />
        Settings
      </span>
    </Link>
    <div className={styles.button} onClick={toggleNightMode}>
      <span>
        <Icon
          name={cx({
            moon: true,
            outline: !isNightModeEnabled
          })}
        />
        Night Mode
      </span>
      <Checkbox toggle checked={isNightModeEnabled} />
    </div>
    <div className={styles.button} onClick={toggleBetaMode}>
      <span>
        <Icon name='flask' />
        Beta Mode
      </span>
      <Checkbox toggle checked={isBetaModeEnabled} />
    </div>
    <Link className={styles.button} to='/account#balance'>
      <span>
        <img src={logo} alt='SANbase' />
        <span>Tokens</span>
      </span>
      {balance}
    </Link>
    <Divider className={styles.divider} />
    <div className={styles.button} onClick={logout}>
      Logout
    </div>
  </div>
)

export default DesktopProfileMenu
