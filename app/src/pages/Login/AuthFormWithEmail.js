import React from 'react'
import { Button, Icon } from 'semantic-ui-react'
import './AuthFormWithEmail.css'

const SignInBtn = ({showForm}) => (
  <Button
    color='green'
    className='sign-in-btn'
    onClick={showForm}
  >
    Sign in with email &nbps; <Icon size='large' name='mail' />
  </Button>
)

const AuthFormWithEmail = (props) => {
  return (
    <div className='auth-form-with-email-wrapper'>
      <SignInBtn />
    </div>
  )
}

export default AuthFormWithEmail
