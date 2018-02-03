import React from 'react'
import { Button } from 'semantic-ui-react'

const EmailLogin = () => {
  return (
    <div>
      <p>To sign up or log in, fill in your email address below:</p>
      <label>Your email</label>
      <input type='text' />
      <Button basic >
        Continue
      </Button>
    </div>
  )
}

export default EmailLogin
