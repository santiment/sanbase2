import React from 'react'
import { Divider, Icon, Checkbox } from 'semantic-ui-react'
import cx from 'classnames'
import { Link } from 'react-router-dom'
import styles from './DesktopProfileMenu.module.css'

const DesktopProfileMenu = ({
  toggleNightMode,
  isNightModeEnabled,
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
    <Divider className={styles.divider} />
    <div className={styles.button} onClick={logout}>
      Logout
    </div>
  </div>
)

export default DesktopProfileMenu
