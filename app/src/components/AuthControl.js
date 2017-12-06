import React from 'react'
import { Button } from 'semantic-ui-react'

const AuthControl = ({user, login, logout}) => {
  if (user.username) {
    return (
      <div className='user-auth-control'>
        You are logged in!
        <br />
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
