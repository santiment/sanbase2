import React, { Fragment } from 'react'
import { Divider, Button } from 'semantic-ui-react'

const AccountSessions = ({ onLogoutBtnClick }) => {
  return (
    <Fragment>
      <h3>Sessions</h3>
      <Divider />
      <div className='account-control'>
        <p>Your current session</p>
        <Button basic color='red' onClick={onLogoutBtnClick}>Log out</Button>
      </div>
    </Fragment>
  )
}

export default AccountSessions
