import React from 'react'
import {
  Button
} from 'semantic-ui-react'
import './AuthControl.css'

const Balance = ({user}) => {
  return (
    <div>{user.ethAccounts.map((account, index) => (
      <div key={index}>
        <div
          type='text'
          className='account-name'>
          {account.address}
        </div>
        <div className='account-balance'>
          <span>SAN: </span>
          <span>{account.sanBalance}</span>
        </div>
      </div>
    ))}</div>
  )
}

const AuthControl = ({user, login, logout}) => {
  if (user.username) {
    return (
      <div className='user-auth-control'>
        You are logged in!
        <Balance user={user} />
        <a href='#' onClick={logout}>
          Log out
        </a>
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Button
        basic
        color='green'
        onClick={login}>
        Log in
      </Button>
    </div>
  )
}

export default AuthControl
