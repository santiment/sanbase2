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
        You are logged in!
        <Balance user={user} />
        <a href='#' onClick={logout}>
          Logout
        </a>
        <br />
        <Link to='/account' >Settings</Link>
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Button
        basic
        color='green'
        onClick={login}>
        Login
      </Button>
    </div>
  )
}

export default AuthControl
