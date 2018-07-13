import React, { Fragment } from 'react'
import { Divider, Button, Checkbox } from 'semantic-ui-react'

const AccountSessions = ({ onLogoutBtnClick, onColorModeToggleChange, isNightModeEnabled }) => {
  return (
    <Fragment>
      <h3>Sessions</h3>
      <Divider />
      <div className='account-control'>
        <p>Your current session</p>
        <Button basic color='red' onClick={onLogoutBtnClick}>Log out</Button>
        <p>Night Mode</p>
        <Checkbox toggle onChange={onColorModeToggleChange} defaultChecked={isNightModeEnabled} />
      </div>
    </Fragment>
  )
}

export default AccountSessions
