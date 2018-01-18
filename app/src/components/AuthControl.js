import React from 'react'
import {
  Button
} from 'semantic-ui-react'
import { Link } from 'react-router-dom'
import Balance from './../components/Balance'
import './AuthControl.css'

const AuthControl = ({user, login, logout}) => {
  if (user.username) {
    return (
      <div className='user-auth-control'>
        <div className='acct'>
          <Balance user={user} />
        </div>
        <div className='acct-links'>
          <ul>
            <li>
              <div className='account-name'>
                <a href='#'>0x34fb639b95d13a492da0d3e8a20de803c2d02dcf</a>
              </div>
            </li>
            <li>
              <Link to='/account' >Settings</Link>
            </li>
            <li><a href='#' onClick={logout}>
              Logout
            </a></li>
          </ul>
        </div>
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Button
        onClick={login}>
        Login
      </Button>
    </div>
  )
}

export default AuthControl
